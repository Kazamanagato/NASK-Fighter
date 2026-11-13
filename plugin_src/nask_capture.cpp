// NASK Capture - plugin do REFramework para o NASK Fighter (Street Fighter 6)
// Copyright (c) 2026 Kazamanagato - licença MIT (veja LICENSE)
//
// O que faz:
//   - tira a foto da tela (backbuffer do DirectX 12) e salva em PNG + miniatura
//   - abre pastas/arquivos no Windows e mostra o seletor de pasta
//
// Como conversa com o script Lua (NASK_Fighter.lua), só por arquivos JSON em
// reframework\data\NASK_Fighter\:
//   status.json   <- escrito ao carregar: {"version":"1.1","default_dir":"..."}
//   request.json  -> pedido do Lua: {"id":N,"cmd":"capture|open|pick_dir", "dir":"...", "path":"..."}
//   result.json   <- resposta: {"id":N,"cmd":"...","ok":true|false,"err":"...","path":"...",
//                               "name":"...","w":W,"h":H,"thumb":"nask_thumbs/..."}
//
// Não lê nem escreve nada fora dessas pastas, a não ser a foto na pasta escolhida.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <d3d12.h>
#include <dxgi1_4.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <ctime>
#include <string>
#include <thread>
#include <vector>

#include "reframework/API.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

static const REFrameworkPluginInitializeParam* g_param = nullptr;

static std::wstring g_data_dir;     // reframework\data\NASK_Fighter\ ...
static std::wstring g_thumb_dir;    // reframework\images\nask_thumbs\ ...
static std::wstring g_default_dir;  // %USERPROFILE%\Pictures\NASK Fighter

static std::atomic<bool> g_busy{false};
static std::atomic<long long> g_last_id{-1};
static FILETIME g_last_req_time{};
static DWORD g_last_poll = 0;

// ---------------------------------------------------------------------------
// utilidades de texto
// ---------------------------------------------------------------------------
static std::wstring utf8_to_w(const std::string& s) {
    if (s.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring w(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
    return w;
}

static std::string w_to_utf8(const std::wstring& w) {
    if (w.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0, nullptr, nullptr);
    std::string s(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), s.data(), n, nullptr, nullptr);
    return s;
}

// texto pronto para ir dentro de aspas no JSON
static std::string json_str(const std::string& s) {
    std::string o;
    for (unsigned char c : s) {
        switch (c) {
        case '\\': o += "\\\\"; break;
        case '"': o += "\\\""; break;
        case '\n': o += "\\n"; break;
        case '\r': o += "\\r"; break;
        case '\t': o += "\\t"; break;
        default:
            if (c < 0x20) { char b[8]; sprintf_s(b, "\\u%04x", c); o += b; }
            else o += (char)c;
        }
    }
    return o;
}

// lê "chave": "texto" ou "chave": número de um JSON simples (o que o Lua escreve)
static bool json_get(const std::string& js, const char* key, std::string& out) {
    std::string k = std::string("\"") + key + "\"";
    size_t p = js.find(k);
    if (p == std::string::npos) return false;
    p = js.find(':', p + k.size());
    if (p == std::string::npos) return false;
    ++p;
    while (p < js.size() && (js[p] == ' ' || js[p] == '\t' || js[p] == '\n' || js[p] == '\r')) ++p;
    if (p >= js.size()) return false;
    out.clear();
    if (js[p] == '"') {
        for (++p; p < js.size() && js[p] != '"'; ++p) {
            if (js[p] == '\\' && p + 1 < js.size()) {
                char e = js[++p];
                switch (e) {
                case 'n': out += '\n'; break;
                case 't': out += '\t'; break;
                case 'r': out += '\r'; break;
                case 'u':
                    if (p + 4 < js.size()) {
                        unsigned cp = (unsigned)strtoul(js.substr(p + 1, 4).c_str(), nullptr, 16);
                        p += 4;
                        wchar_t wc = (wchar_t)cp;
                        out += w_to_utf8(std::wstring(1, wc));
                    }
                    break;
                default: out += e;
                }
            } else {
                out += js[p];
            }
        }
        return true;
    }
    while (p < js.size() && js[p] != ',' && js[p] != '}' && js[p] != ' ' && js[p] != '\n' && js[p] != '\r') out += js[p++];
    return !out.empty();
}

static bool read_file(const std::wstring& path, std::string& out) {
    HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER sz{};
    GetFileSizeEx(h, &sz);
    out.resize((size_t)sz.QuadPart);
    DWORD rd = 0;
    BOOL ok = sz.QuadPart == 0 || ReadFile(h, out.data(), (DWORD)sz.QuadPart, &rd, nullptr);
    CloseHandle(h);
    return ok;
}

// escreve num temporário e troca: o Lua nunca lê um arquivo pela metade
static void write_file_atomic(const std::wstring& path, const std::string& data) {
    std::wstring tmp = path + L".tmp";
    HANDLE h = CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return;
    DWORD wr = 0;
    WriteFile(h, data.data(), (DWORD)data.size(), &wr, nullptr);
    CloseHandle(h);
    MoveFileExW(tmp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING);
}

static void make_dirs(const std::wstring& dir) {
    // cria cada nível do caminho
    for (size_t i = 3; i < dir.size(); ++i) {
        if (dir[i] == L'\\' || dir[i] == L'/') CreateDirectoryW(dir.substr(0, i).c_str(), nullptr);
    }
    CreateDirectoryW(dir.c_str(), nullptr);
}

static std::wstring with_slash(std::wstring d) {
    if (!d.empty() && d.back() != L'\\' && d.back() != L'/') d += L'\\';
    return d;
}

static std::wstring full_path(const std::wstring& rel) {
    wchar_t buf[MAX_PATH * 4];
    DWORD n = GetFullPathNameW(rel.c_str(), MAX_PATH * 4, buf, nullptr);
    return (n > 0 && n < MAX_PATH * 4) ? std::wstring(buf, n) : rel;
}

// ---------------------------------------------------------------------------
// respostas
// ---------------------------------------------------------------------------
static void write_result(long long id, const char* cmd, bool ok, const std::string& err,
                         const std::string& path = "", const std::string& name = "",
                         int w = 0, int h = 0, const std::string& thumb = "") {
    std::string js = "{\"id\":" + std::to_string(id) + ",\"cmd\":\"" + cmd + "\",\"ok\":" + (ok ? "true" : "false");
    if (!err.empty()) js += ",\"err\":\"" + json_str(err) + "\"";
    if (!path.empty()) js += ",\"path\":\"" + json_str(path) + "\"";
    if (!name.empty()) js += ",\"name\":\"" + json_str(name) + "\"";
    if (w > 0) js += ",\"w\":" + std::to_string(w) + ",\"h\":" + std::to_string(h);
    if (!thumb.empty()) js += ",\"thumb\":\"" + json_str(thumb) + "\"";
    js += "}";
    write_file_atomic(g_data_dir + L"result.json", js);
}

static void write_status() {
    std::string js = "{\"version\":\"1.1\",\"default_dir\":\"" + json_str(w_to_utf8(g_default_dir)) + "\"}";
    write_file_atomic(g_data_dir + L"status.json", js);
}

// ---------------------------------------------------------------------------
// salvar a foto (roda numa thread, fora do frame do jogo)
// ---------------------------------------------------------------------------
struct Shot {
    long long id = 0;
    std::wstring dir;
    int w = 0, h = 0;
    std::vector<uint8_t> rgba;  // já convertido para RGBA 8 bits, sem padding
};

static void save_thread(Shot* shot) {
    std::wstring dir = with_slash(shot->dir.empty() ? g_default_dir : shot->dir);
    make_dirs(dir);

    time_t t = time(nullptr);
    tm lt{};
    localtime_s(&lt, &t);
    wchar_t fname[96];
    swprintf_s(fname, L"NASK_%04d-%02d-%02d_%02d-%02d-%02d.png", lt.tm_year + 1900, lt.tm_mon + 1, lt.tm_mday,
               lt.tm_hour, lt.tm_min, lt.tm_sec);
    std::wstring name = fname;
    // não sobrescreve se tirar duas fotos no mesmo segundo
    for (int i = 2; GetFileAttributesW((dir + name).c_str()) != INVALID_FILE_ATTRIBUTES && i < 100; ++i) {
        swprintf_s(fname, L"NASK_%04d-%02d-%02d_%02d-%02d-%02d_%d.png", lt.tm_year + 1900, lt.tm_mon + 1,
                   lt.tm_mday, lt.tm_hour, lt.tm_min, lt.tm_sec, i);
        name = fname;
    }

    int len = 0;
    unsigned char* png = stbi_write_png_to_mem(shot->rgba.data(), shot->w * 4, shot->w, shot->h, 4, &len);
    bool ok = false;
    if (png) {
        HANDLE fh = CreateFileW((dir + name).c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (fh != INVALID_HANDLE_VALUE) {
            DWORD wr = 0;
            ok = WriteFile(fh, png, (DWORD)len, &wr, nullptr) && wr == (DWORD)len;
            CloseHandle(fh);
        }
        STBIW_FREE(png);
    }
    if (!ok) {
        write_result(shot->id, "capture", false, "falha ao salvar o PNG (pasta sem permissão ou disco cheio)");
        delete shot;
        g_busy = false;
        return;
    }

    // miniatura de 320 px de largura para a galeria (média de blocos)
    std::string thumb_rel;
    {
        const int tw = 320;
        const int th = (int)((long long)shot->h * tw / (shot->w > 0 ? shot->w : 1));
        if (th > 0) {
            std::vector<uint8_t> small((size_t)tw * th * 4);
            for (int y = 0; y < th; ++y) {
                int y0 = (int)((long long)y * shot->h / th), y1 = (int)((long long)(y + 1) * shot->h / th);
                if (y1 <= y0) y1 = y0 + 1;
                for (int x = 0; x < tw; ++x) {
                    int x0 = (int)((long long)x * shot->w / tw), x1 = (int)((long long)(x + 1) * shot->w / tw);
                    if (x1 <= x0) x1 = x0 + 1;
                    unsigned sum[4] = {0, 0, 0, 0}, n = 0;
                    for (int yy = y0; yy < y1; yy += 2)
                        for (int xx = x0; xx < x1; xx += 2) {
                            const uint8_t* p = &shot->rgba[((size_t)yy * shot->w + xx) * 4];
                            sum[0] += p[0]; sum[1] += p[1]; sum[2] += p[2]; ++n;
                        }
                    uint8_t* q = &small[((size_t)y * tw + x) * 4];
                    q[0] = (uint8_t)(sum[0] / n); q[1] = (uint8_t)(sum[1] / n); q[2] = (uint8_t)(sum[2] / n); q[3] = 255;
                }
            }
            int tlen = 0;
            unsigned char* tpng = stbi_write_png_to_mem(small.data(), tw * 4, tw, th, 4, &tlen);
            if (tpng) {
                make_dirs(g_thumb_dir);
                HANDLE fh = CreateFileW((g_thumb_dir + name).c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
                if (fh != INVALID_HANDLE_VALUE) {
                    DWORD wr = 0;
                    if (WriteFile(fh, tpng, (DWORD)tlen, &wr, nullptr)) thumb_rel = "nask_thumbs/" + w_to_utf8(name);
                    CloseHandle(fh);
                }
                STBIW_FREE(tpng);
            }
        }
    }

    write_result(shot->id, "capture", true, "", w_to_utf8(full_path(dir + name)), w_to_utf8(name), shot->w, shot->h, thumb_rel);
    delete shot;
    g_busy = false;
}

// ---------------------------------------------------------------------------
// captura do backbuffer (DirectX 12), chamada no on_present
// ---------------------------------------------------------------------------
static inline uint8_t to8_10(uint32_t v) { return (uint8_t)((v * 255 + 511) / 1023); }

static bool capture_backbuffer(Shot* shot, std::string& err) {
    const REFrameworkRendererData* rd = g_param->renderer_data;
    if (rd->renderer_type != REFRAMEWORK_RENDERER_D3D12) { err = "a captura só funciona em DirectX 12"; return false; }

    auto* swap = (IDXGISwapChain3*)rd->swapchain;
    auto* dev = (ID3D12Device*)rd->device;
    auto* queue = (ID3D12CommandQueue*)rd->command_queue;
    if (!swap || !dev || !queue) { err = "renderer do REFramework indisponível"; return false; }

    ID3D12Resource* back = nullptr;
    if (FAILED(swap->GetBuffer(swap->GetCurrentBackBufferIndex(), IID_PPV_ARGS(&back)))) { err = "falha ao ler a foto"; return false; }
    D3D12_RESOURCE_DESC desc = back->GetDesc();

    D3D12_PLACED_SUBRESOURCE_FOOTPRINT fp{};
    UINT64 total = 0;
    dev->GetCopyableFootprints(&desc, 0, 1, 0, &fp, nullptr, nullptr, &total);

    D3D12_HEAP_PROPERTIES hp{};
    hp.Type = D3D12_HEAP_TYPE_READBACK;
    D3D12_RESOURCE_DESC bd{};
    bd.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    bd.Width = total;
    bd.Height = 1;
    bd.DepthOrArraySize = 1;
    bd.MipLevels = 1;
    bd.SampleDesc.Count = 1;
    bd.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;

    ID3D12Resource* rb = nullptr;
    ID3D12CommandAllocator* alloc = nullptr;
    ID3D12GraphicsCommandList* list = nullptr;
    ID3D12Fence* fence = nullptr;
    HANDLE ev = nullptr;
    bool ok = false;

    do {
        if (FAILED(dev->CreateCommittedResource(&hp, D3D12_HEAP_FLAG_NONE, &bd, D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&rb)))) { err = "falha ao ler a foto"; break; }
        if (FAILED(dev->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&alloc)))) { err = "falha no command allocator"; break; }
        if (FAILED(dev->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc, nullptr, IID_PPV_ARGS(&list)))) { err = "falha na command list"; break; }

        D3D12_RESOURCE_BARRIER b{};
        b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        b.Transition.pResource = back;
        b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        b.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
        b.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
        list->ResourceBarrier(1, &b);

        D3D12_TEXTURE_COPY_LOCATION src{}, dst{};
        src.pResource = back;
        src.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        src.SubresourceIndex = 0;
        dst.pResource = rb;
        dst.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
        dst.PlacedFootprint = fp;
        list->CopyTextureRegion(&dst, 0, 0, 0, &src, nullptr);

        b.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_SOURCE;
        b.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
        list->ResourceBarrier(1, &b);
        list->Close();

        ID3D12CommandList* lists[] = {list};
        queue->ExecuteCommandLists(1, lists);

        if (FAILED(dev->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)))) { err = "falha no fence"; break; }
        ev = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        queue->Signal(fence, 1);
        if (fence->GetCompletedValue() < 1) {
            fence->SetEventOnCompletion(1, ev);
            WaitForSingleObject(ev, 2000);
        }

        void* mapped = nullptr;
        D3D12_RANGE range{0, (SIZE_T)total};
        if (FAILED(rb->Map(0, &range, &mapped))) { err = "falha ao ler a foto"; break; }

        const int w = (int)desc.Width, h = (int)desc.Height;
        shot->w = w;
        shot->h = h;
        shot->rgba.resize((size_t)w * h * 4);
        const uint8_t* base = (const uint8_t*)mapped + fp.Offset;
        const UINT pitch = fp.Footprint.RowPitch;
        bool fmt_ok = true;

        for (int y = 0; y < h && fmt_ok; ++y) {
            const uint8_t* row = base + (size_t)y * pitch;
            uint8_t* out = &shot->rgba[(size_t)y * w * 4];
            switch (desc.Format) {
            case DXGI_FORMAT_R8G8B8A8_UNORM:
            case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:
            case DXGI_FORMAT_R8G8B8A8_TYPELESS:
                for (int x = 0; x < w; ++x) {
                    out[x * 4 + 0] = row[x * 4 + 0];
                    out[x * 4 + 1] = row[x * 4 + 1];
                    out[x * 4 + 2] = row[x * 4 + 2];
                    out[x * 4 + 3] = 255;
                }
                break;
            case DXGI_FORMAT_B8G8R8A8_UNORM:
            case DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:
            case DXGI_FORMAT_B8G8R8A8_TYPELESS:
                for (int x = 0; x < w; ++x) {
                    out[x * 4 + 0] = row[x * 4 + 2];
                    out[x * 4 + 1] = row[x * 4 + 1];
                    out[x * 4 + 2] = row[x * 4 + 0];
                    out[x * 4 + 3] = 255;
                }
                break;
            case DXGI_FORMAT_R10G10B10A2_UNORM:
            case DXGI_FORMAT_R10G10B10A2_TYPELESS:
                for (int x = 0; x < w; ++x) {
                    uint32_t v;
                    memcpy(&v, row + x * 4, 4);
                    out[x * 4 + 0] = to8_10(v & 1023);
                    out[x * 4 + 1] = to8_10((v >> 10) & 1023);
                    out[x * 4 + 2] = to8_10((v >> 20) & 1023);
                    out[x * 4 + 3] = 255;
                }
                break;
            default:
                fmt_ok = false;
            }
        }
        D3D12_RANGE none{0, 0};
        rb->Unmap(0, &none);
        if (!fmt_ok) {
            char b2[96];
            sprintf_s(b2, "formato de tela não suportado (%d)", (int)desc.Format);
            err = b2;
            break;
        }
        ok = true;
    } while (false);

    if (ev) CloseHandle(ev);
    if (fence) fence->Release();
    if (list) list->Release();
    if (alloc) alloc->Release();
    if (rb) rb->Release();
    back->Release();
    return ok;
}

// ---------------------------------------------------------------------------
// seletor de pasta (thread própria para não travar o jogo)
// ---------------------------------------------------------------------------
static void pick_thread(long long id) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    BROWSEINFOW bi{};
    bi.lpszTitle = L"NASK Fighter - escolha a pasta das fotos";
    bi.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE;
    PIDLIST_ABSOLUTE pidl = SHBrowseForFolderW(&bi);
    if (pidl) {
        wchar_t path[MAX_PATH];
        if (SHGetPathFromIDListW(pidl, path)) write_result(id, "pick_dir", true, "", w_to_utf8(path));
        else write_result(id, "pick_dir", false, "cancelado");
        CoTaskMemFree(pidl);
    } else {
        write_result(id, "pick_dir", false, "cancelado");
    }
    CoUninitialize();
}

// ---------------------------------------------------------------------------
// pedidos do Lua (lidos no máximo 10x por segundo)
// ---------------------------------------------------------------------------
static void poll_request() {
    DWORD now = GetTickCount();
    if (now - g_last_poll < 100) return;
    g_last_poll = now;

    std::wstring req = g_data_dir + L"request.json";
    WIN32_FILE_ATTRIBUTE_DATA fa{};
    if (!GetFileAttributesExW(req.c_str(), GetFileExInfoStandard, &fa)) return;
    if (CompareFileTime(&fa.ftLastWriteTime, &g_last_req_time) == 0) return;

    std::string js;
    if (!read_file(req, js)) return;
    std::string sid, cmd;
    if (!json_get(js, "id", sid) || !json_get(js, "cmd", cmd)) return;   // arquivo ainda sendo escrito
    g_last_req_time = fa.ftLastWriteTime;
    long long id = _atoi64(sid.c_str());
    if (id == g_last_id) return;
    g_last_id = id;

    if (cmd == "capture") {
        if (g_busy) { write_result(id, "capture", false, "ainda salvando a foto anterior"); return; }
        std::string dir;
        json_get(js, "dir", dir);
        auto* shot = new Shot();
        shot->id = id;
        shot->dir = utf8_to_w(dir);
        std::string err;
        if (!capture_backbuffer(shot, err)) {
            write_result(id, "capture", false, err);
            delete shot;
            return;
        }
        g_busy = true;
        std::thread(save_thread, shot).detach();
    } else if (cmd == "open") {
        std::string path;
        if (json_get(js, "path", path) && !path.empty()) {
            ShellExecuteW(nullptr, L"open", utf8_to_w(path).c_str(), nullptr, nullptr, SW_SHOWNORMAL);
        }
        write_result(id, "open", true, "");
    } else if (cmd == "pick_dir") {
        std::thread(pick_thread, id).detach();
    } else {
        write_result(id, cmd.c_str(), false, "comando desconhecido");
    }
}

static void on_present() {
    poll_request();
}

// ---------------------------------------------------------------------------
// entrada do plugin
// ---------------------------------------------------------------------------
extern "C" __declspec(dllexport) void reframework_plugin_required_version(REFrameworkPluginVersion* version) {
    version->major = REFRAMEWORK_PLUGIN_VERSION_MAJOR;
    version->minor = REFRAMEWORK_PLUGIN_VERSION_MINOR;
    version->patch = REFRAMEWORK_PLUGIN_VERSION_PATCH;
}

extern "C" __declspec(dllexport) bool reframework_plugin_initialize(const REFrameworkPluginInitializeParam* param) {
    g_param = param;

    // o jogo roda com a pasta do .exe como pasta atual (é onde fica a pasta reframework)
    g_data_dir = with_slash(full_path(L"reframework\\data\\NASK_Fighter"));
    g_thumb_dir = with_slash(full_path(L"reframework\\images\\nask_thumbs"));
    make_dirs(g_data_dir);
    make_dirs(g_thumb_dir);

    wchar_t pics[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_MYPICTURES, nullptr, 0, pics))) {
        g_default_dir = std::wstring(pics) + L"\\NASK Fighter";
    } else {
        wchar_t prof[MAX_PATH];
        DWORD n = GetEnvironmentVariableW(L"USERPROFILE", prof, MAX_PATH);
        g_default_dir = (n > 0 ? std::wstring(prof) : std::wstring(L"C:")) + L"\\Pictures\\NASK Fighter";
    }

    // ignora um request.json que tenha sobrado da última vez
    WIN32_FILE_ATTRIBUTE_DATA fa{};
    if (GetFileAttributesExW((g_data_dir + L"request.json").c_str(), GetFileExInfoStandard, &fa)) g_last_req_time = fa.ftLastWriteTime;

    write_status();
    param->functions->on_present(on_present);
    param->functions->log_info("[NASK Capture] carregado v1.1");
    return true;
}

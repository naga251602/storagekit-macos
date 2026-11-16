// StorageKit v5: READ-ONLY discovery engine.
// Structured JSON Lines interface consumed by the SwiftUI front end.
#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cstdint>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <optional>
#include <set>
#include <string>
#include <vector>
#include <sys/stat.h>
#ifdef __APPLE__
#include <CoreFoundation/CoreFoundation.h>
#else
#include <fstream>
#include <regex>
#endif

namespace fs = std::filesystem;
using std::string;

struct App { fs::path path; string name, bundleID; };
struct SizeInfo { uint64_t bytes=0, files=0; bool complete=true; };
struct Snapshot { uint64_t device=0, inode=0; int64_t mtime=0; bool valid=false; };
struct Entry {
    string type="candidate", category, status="GREY", confidence="review", reason, cleanup="none", bundleID;
    fs::path path;
    bool eligible=false;
    SizeInfo size;
    Snapshot snapshot;
};

static string lower(string s) {
    std::transform(s.begin(),s.end(),s.begin(),[](unsigned char c){return (char)std::tolower(c);}); return s;
}
static bool startsWith(const string& s, const string& prefix) { return s.rfind(prefix,0)==0; }
static bool appleID(const string& id) { string s=lower(id); return startsWith(s,"com.apple.") || s=="com.apple"; }
static bool isUnder(const fs::path& path, const fs::path& dir) {
    fs::path a=path.lexically_normal(), b=dir.lexically_normal();
    auto it=a.begin(); for(auto part: b){ if(it==a.end() || *it!=part) return false; ++it; }
    return it!=a.end();
}
static bool hasSymlinkComponent(const fs::path& p) {
    auto a=fs::absolute(p).lexically_normal();
    fs::path current;
    std::error_code ec;
    for (const auto& part: a) {
        current /= part;
        if(fs::is_symlink(fs::symlink_status(current,ec))) return true;
        if(ec) { ec.clear(); /* Could be inaccessible; the final preflight will reject it. */ }
    }
    return false;
}
static bool protectedPath(const fs::path& path) {
    auto p=path.lexically_normal();
    if(!p.is_absolute() || p==p.root_path()) return true;
    static const std::vector<fs::path> blocked={"/System","/Library","/usr","/bin","/sbin","/private","/etc","/dev","/opt","/Volumes","/Network"};
    for (auto& root: blocked) if(p==root || isUnder(p,root)) return true;
    return false;
}
static Snapshot snapshot(const fs::path& p) {
    struct stat st{}; auto s=p.string(); if(lstat(s.c_str(),&st)!=0) return {};
#ifdef __APPLE__
    return {(uint64_t)st.st_dev,(uint64_t)st.st_ino,(int64_t)st.st_mtimespec.tv_sec,true};
#else
    return {(uint64_t)st.st_dev,(uint64_t)st.st_ino,(int64_t)st.st_mtim.tv_sec,true};
#endif
}
static SizeInfo sizeOf(const fs::path& path) {
    SizeInfo result;
    std::error_code ec;
    const auto st=fs::symlink_status(path,ec);
    if(ec) {result.complete=false;return result;}
    if(fs::is_symlink(st)) {result.complete=false;return result;}
    if(fs::is_regular_file(st)) {
        result.bytes=fs::file_size(path,ec); result.files=1;
        if(ec) {result.complete=false;result.bytes=0;}
        return result;
    }
    if(!fs::is_directory(st)) {result.complete=false;return result;}
    // Never follow directory symlinks, including inside app bundles and caches.
    fs::recursive_directory_iterator it(path,fs::directory_options::none,ec),end;
    if(ec) {result.complete=false; return result;}
    const uint64_t limit=300000;
    uint64_t visited=0;
    for(;it!=end;) {
        if(++visited>limit) {result.complete=false;break;}
        auto item=it->symlink_status(ec);
        if(ec) {result.complete=false;ec.clear();}
        else if(fs::is_symlink(item)) {it.disable_recursion_pending();}
        else if(fs::is_regular_file(item)) {
            auto bytes=it->file_size(ec);
            if(ec) {result.complete=false;ec.clear();}
            else {result.bytes+=bytes;result.files++;}
        }
        it.increment(ec);
        if(ec) {result.complete=false;ec.clear();break;}
    }
    return result;
}
#ifdef __APPLE__
static string readBundleID(const fs::path& bundle) {
    const auto path=(bundle/"Contents/Info.plist").string();
    auto url=CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
               reinterpret_cast<const UInt8*>(path.data()),path.size(),false);
    if(!url) return {};
    auto stream=CFReadStreamCreateWithFile(kCFAllocatorDefault,url); CFRelease(url);
    if(!stream) return {};
    string out;
    if(CFReadStreamOpen(stream)) {
        std::vector<UInt8> bytes; UInt8 buf[8192]; CFIndex n;
        while((n=CFReadStreamRead(stream,buf,sizeof buf))>0 && bytes.size()<4000000)
            bytes.insert(bytes.end(),buf,buf+n);
        CFReadStreamClose(stream);
        if(!bytes.empty()) {
            CFDataRef data=CFDataCreate(kCFAllocatorDefault,bytes.data(),bytes.size());
            if(data) {
                CFPropertyListRef plist=CFPropertyListCreateWithData(kCFAllocatorDefault,data,kCFPropertyListImmutable,nullptr,nullptr);
                if(plist) {
                    if(CFGetTypeID(plist)==CFDictionaryGetTypeID()) {
                        CFTypeRef id=CFDictionaryGetValue((CFDictionaryRef)plist,CFSTR("CFBundleIdentifier"));
                        if(id && CFGetTypeID(id)==CFStringGetTypeID()) {
                            char result[4096];
                            if(CFStringGetCString((CFStringRef)id,result,sizeof(result),kCFStringEncodingUTF8)) out=result;
                        }
                    }
                    CFRelease(plist);
                }
                CFRelease(data);
            }
        }
    }
    CFRelease(stream);return out;
}
#else
static string readBundleID(const fs::path& bundle) { // XML-plist fixture reader for portable tests only.
    std::ifstream in(bundle/"Contents/Info.plist");
    if(!in) return {};
    string s((std::istreambuf_iterator<char>(in)),{});
    std::regex pattern(R"(<key>\s*CFBundleIdentifier\s*</key>\s*<string>\s*([^<]+?)\s*</string>)");
    std::smatch m; return std::regex_search(s,m,pattern)?m[1].str():string{};
}
#endif
static void enumerateApps(const fs::path& root,std::vector<App>& apps) {
    std::error_code ec;
    if(!fs::is_directory(root,ec)) return;
    fs::recursive_directory_iterator it(root,fs::directory_options::skip_permission_denied,ec),end;
    if(ec) return;
    for(;it!=end;) {
        if(it->path().extension()==".app" && it->is_directory(ec)) {
            auto p=it->path().lexically_normal();
            apps.push_back({p,p.stem().string(),readBundleID(p)});
            it.disable_recursion_pending();
        } else if(it.depth()>4) it.disable_recursion_pending();
        ec.clear();it.increment(ec);
        if(ec) ec.clear();
    }
}
static bool safeAppLocation(const fs::path& path, const fs::path& home) {
    return isUnder(path,"/Applications") || isUnder(path,home/"Applications");
}
static Entry entry(const fs::path& p,const string& type,const string& category,const string& status,
                   const string& confidence,const string& reason,const string& cleanup,bool eligible,
                   const string& bundleID,bool sizes) {
    Entry e; e.type=type;e.path=p.lexically_normal();e.category=category;e.status=status;
    e.confidence=confidence;e.reason=reason;e.cleanup=cleanup;e.eligible=eligible;e.bundleID=bundleID;
    e.snapshot=snapshot(e.path);
    if(sizes) e.size=sizeOf(e.path);
    else e.size.complete=false;
    if(!e.snapshot.valid || hasSymlinkComponent(e.path) || protectedPath(e.path)) {
        e.eligible=false;
        if(hasSymlinkComponent(e.path)) {e.status="GREY";e.reason+="; symlink path blocked";}
        if(protectedPath(e.path)) {e.status="RED";e.reason+="; protected location";}
    }
    if(sizes && !e.size.complete) {e.eligible=false; e.reason+="; size/contents not fully readable";}
    return e;
}
static std::vector<Entry> discoverApp(const App& app,const fs::path& home,bool sizes) {
    std::vector<Entry> result;
    const bool protectedBundle=protectedPath(app.path) || startsWith(app.path.string(),"/System/");
    const bool apple=appleID(app.bundleID);
    const bool allowed=!protectedBundle && !apple && !app.bundleID.empty() && safeAppLocation(app.path,home);
    // System-installed Apple apps are inspectable, but their .app bundles never
    // become cleanup candidates. Only exact, user-owned Library matches may be
    // individually reviewed in Advanced Mode.
    result.push_back(entry(app.path,"candidate","Application",protectedBundle?"RED":apple?"AMBER":allowed?"GREEN":"GREY",
        allowed?"high":"review",allowed?"Installed application bundle; bundle ID verified":
        apple && !protectedBundle?"Apple-authored app in ordinary Applications path; manual review only":"Protected or unverified app bundle",
        "app",allowed,app.bundleID,sizes));
    // Each listed root is inspected only one level deep. No recursive fuzzy filename search.
    struct Root {fs::path path;string category;bool shared;bool reviewOnly;};
    const std::vector<Root> roots={
        {home/"Library/Application Support","Application Support",false,false},
        {home/"Library/Caches","Caches",false,false},
        {home/"Library/Preferences","Preferences",false,false},
        {home/"Library/Containers","Containers",false,false},
        {home/"Library/Group Containers","Group Containers",true,true},
        {home/"Library/Logs","Logs",false,false},
        {home/"Library/Saved Application State","Saved Application State",false,false},
        {home/"Library/HTTPStorages","HTTPStorages",false,false},
        {home/"Library/WebKit","WebKit",false,false},
        {home/"Library/LaunchAgents","Launch Agents",false,true},
        {fs::path("/Library/Application Support"),"System-wide Support",true,true},
        {fs::path("/Library/LaunchAgents"),"System Launch Agents",true,true},
        {fs::path("/Library/LaunchDaemons"),"Launch Daemons",true,true},
        {fs::path("/Library/PrivilegedHelperTools"),"Privileged Helpers",true,true}
    };
    const string lname=lower(app.name),lid=lower(app.bundleID);
    for(const auto& root: roots) {
        std::error_code ec;
        fs::directory_iterator it(root.path,fs::directory_options::skip_permission_denied,ec),end;
        if(ec) continue;
        for(;it!=end;) {
            auto p=it->path();
            const string filename=lower(p.filename().string());
            const bool exactID= !lid.empty() && (filename==lid ||
                (root.category=="Preferences" && filename==lid+".plist") ||
                (root.category=="Saved Application State" && filename==lid+".savedstate"));
            const bool exactName= !lname.empty() && filename==lname;
            const bool partialID= !lid.empty() && startsWith(filename,lid+".");
            if(exactID||exactName||partialID) {
                const bool ownHistory=p.lexically_normal()==(home/"Library/Application Support/StorageKit").lexically_normal();
                const bool high=exactID && !root.reviewOnly && !apple && !protectedBundle && !ownHistory;
                // A protected app bundle must NOT turn unrelated user-owned
                // caches RED. The path itself determines filesystem protection.
                const bool knownProtected=protectedPath(p)||ownHistory;
                const bool appleReview=apple && exactID && !root.reviewOnly && !knownProtected;
                string reason=high?"Exact bundle-ID match in dedicated app-data directory":
                    appleReview?"Apple app user Library data; manual Advanced review required; may include synced personal data":
                    exactID?"Exact bundle ID, but shared/system-wide ownership":
                    exactName?"Exact app name only; ownership not established":"Bundle-ID prefix only; ownership not established";
                if(root.shared) reason+="; potentially shared";
                const string action=root.category=="Caches"?"cache":"data";
                result.push_back(entry(p,"candidate",root.category,
                    knownProtected?"RED":(root.shared||appleReview)?"AMBER":high?"GREEN":"GREY",
                    high?"high":"review",reason,action,high,app.bundleID,sizes));
            }
            ec.clear();it.increment(ec);if(ec) ec.clear();
        }
    }
    // Ollama keeps downloaded LLMs, logs and configuration outside ~/Library.
    // These are vendor-documented uninstall paths, not fuzzy name matches.
    // Moving ~/.ollama as ONE unit also includes logs, custom models and keys;
    // no child of it is selected separately (avoids duplicate/overlapping moves).
    const bool ollama=(lower(app.name)=="ollama" &&
        (lid=="com.electron.ollama" || lid=="com.ollama.ollama"));
    if(ollama && allowed) {
        const std::vector<std::pair<fs::path,string>> known={
            {home/".ollama","Ollama Models & Configuration"},
            {home/"Library/Application Support/Ollama","Application Support"},
            {home/"Library/Caches/ollama","Caches"},
            {home/"Library/Caches/com.electron.ollama","Caches"},
            {home/"Library/Preferences/com.electron.ollama.plist","Preferences"},
            {home/"Library/Saved Application State/com.electron.ollama.savedState","Saved Application State"},
            {home/"Library/WebKit/com.electron.ollama","WebKit"}
        };
        for(const auto& [p,category]:known) {
            std::error_code ec;
            if(!fs::exists(p,ec) || ec) continue;
            // Avoid duplicate entries when a regular root match already found it.
            bool exists=std::any_of(result.begin(),result.end(),[&](const Entry& e){return e.path==p;});
            if(exists) {
                for(auto& e:result) if(e.path==p && !e.eligible && !protectedPath(p)
                  && !hasSymlinkComponent(p)) {
                    e.status="GREEN";e.confidence="high";e.eligible=true;
                    e.reason="Vendor-documented Ollama data path; may include models, credentials or history";
                }
                continue;
            }
            result.push_back(entry(p,"candidate",category,"GREEN","high",
                "Vendor-documented Ollama data; includes downloaded models, logs, settings or keys",
                category=="Caches"?"cache":"data",true,app.bundleID,sizes));
        }
        // /usr/local/bin/ollama is an optional privileged CLI symlink: show for
        // manual follow-up, never auto-move or bypass macOS/ownership protections.
        fs::path cli="/usr/local/bin/ollama";
        std::error_code ec;
        if(fs::exists(cli,ec) || fs::is_symlink(fs::symlink_status(cli,ec))) {
            result.push_back(entry(cli,"candidate","CLI Link","RED","review",
                "Optional Ollama CLI link; outside StorageKit's user-owned Trash scope",
                "none",false,app.bundleID,sizes));
        }
    }
    std::set<string> seen;
    std::vector<Entry> unique;
    for(auto& e:result) if(seen.insert(e.path.string()).second) unique.push_back(std::move(e));
    return unique;
}
static void addInventory(std::vector<Entry>& out,const fs::path& p,const string& category,const string& why,bool sizes) {
    std::error_code ec;
    if(!fs::exists(p,ec) || ec || hasSymlinkComponent(p)) return;
    // Only known, user-scoped cache/model stores and runtime directories can be
    // manually selected. Homebrew packages and shared Ollama manifests must be
    // removed through their own manager, not by deleting the package directory.
    const bool reviewable = category=="Runtime/environment" || category=="Cache/model store"
        || category=="Developer data" || category=="Hugging Face cached model";
    out.push_back(entry(p,"inventory",category,reviewable?"AMBER":"GREY",
        reviewable?"manual":"inventory",
        reviewable ? why+"; manually selectable, may break dependencies" : why,
        reviewable?"developer":"none",false,"",sizes));
}
static void inventoryChildren(std::vector<Entry>& out,const fs::path& root,const string& category,const string& why,bool sizes) {
    std::error_code ec;fs::directory_iterator it(root,fs::directory_options::skip_permission_denied,ec),end;
    for(;it!=end;) {addInventory(out,it->path(),category,why,sizes);ec.clear();it.increment(ec);if(ec)ec.clear();}
}
static std::vector<Entry> inventory(const fs::path& home,bool sizes) {
    std::vector<Entry> out;
    inventoryChildren(out,"/opt/homebrew/Cellar","Homebrew formula","Managed by Homebrew; inventory only",sizes);
    inventoryChildren(out,"/opt/homebrew/Caskroom","Homebrew cask","Managed by Homebrew; inventory only",sizes);
    inventoryChildren(out,"/usr/local/Cellar","Homebrew formula","Managed by Homebrew; inventory only",sizes);
    inventoryChildren(out,"/usr/local/Caskroom","Homebrew cask","Managed by Homebrew; inventory only",sizes);
    for(const auto& p:{".nvm/versions/node",".pyenv/versions",".local/share/uv/python","miniconda3/envs","anaconda3/envs","miniforge3/envs",".conda/envs"})
        inventoryChildren(out,home/p,"Runtime/environment","May be used by projects; inventory only",sizes);
    for(const auto& p:{".npm",".cache/pip","Library/Caches/pip",".cache/uv",".cache/huggingface/hub",".cache/torch/hub",".ollama/models","Library/Application Support/LM Studio/models","Library/Application Support/Jan/models",".cache/lm-studio/models"})
        addInventory(out,home/p,"Cache/model store","Shared cache or model store; inventory only",sizes);
    // One Hugging Face repository is a self-contained cache subtree; present it
    // separately for users who don't want to trash the entire hub cache.
    {
        std::error_code ec;
        const auto hub=home/".cache/huggingface/hub";
        fs::directory_iterator it(hub,fs::directory_options::skip_permission_denied,ec),end;
        for(;!ec && it!=end;it.increment(ec)) {
            const auto path=it->path();
            if(startsWith(path.filename().string(),"models--")
               && fs::is_directory(fs::symlink_status(path,ec)) && !ec) {
                addInventory(out,path,"Hugging Face cached model",
                    "One cached model repository; may be shared by projects",sizes);
            }
            ec.clear();
        }
    }
    inventoryChildren(out,home/".ollama/models/manifests/registry.ollama.ai/library","Ollama model manifest","Blobs are shared; inventory only",sizes);
    for(const auto& p:{".local/share/virtualenvs","Library/Python",".bun/install/cache",".pnpm-store",".yarn/berry/cache",".cargo/registry",".rustup/toolchains"})
        addInventory(out,home/p,"Developer data","Shared developer data; inventory only",sizes);
    return out;
}
// Storage-wide candidates are never inferred to be safe from a filename alone.
// Managed package caches and model blobs remain inventory-only: no raw filesystem
// Trash action may claim to be a package-manager cleanup operation.
static std::vector<Entry> storageCandidates(const fs::path& home, bool sizes,
                                            const std::vector<App>& apps) {
    std::vector<Entry> out;
    std::set<string> seen;
    auto add = [&](const fs::path& path, const string& category,
                   const string& status, const string& reason,
                   const string& bundleID, bool verified) {
        auto normalized = path.lexically_normal();
        if (!seen.insert(normalized.string()).second) return;
        std::error_code ec;
        if (!fs::exists(normalized, ec) || ec) return;
        out.push_back(entry(normalized, "storage", category, status,
            verified ? "high" : "review", reason, "cache", verified, bundleID, sizes));
    };
    // Only exact bundle-ID named directories are automatically eligible.
    for (const auto& app : apps) {
        if (app.bundleID.empty() || appleID(app.bundleID) || !safeAppLocation(app.path, home)) continue;
        const auto p = home / "Library/Caches" / app.bundleID;
        add(p, "App Cache", "GREEN", "Exact bundle-ID cache for installed app " + app.name,
            app.bundleID, true);
    }
    auto children = [&](const fs::path& root, const string& category,
                        const string& why, int maxItems, int minAgeDays) {
        std::error_code ec;
        fs::directory_iterator it(root, fs::directory_options::skip_permission_denied, ec), end;
        int count = 0;
        for (; !ec && it != end && count < maxItems; it.increment(ec)) {
            auto p = it->path();
            if (appleID(p.filename().string())) continue; // Skip Apple-owned cleanup candidates.
            if (fs::is_symlink(fs::symlink_status(p, ec))) { ec.clear(); continue; }
            if (ec) { ec.clear(); continue; }
            if (minAgeDays > 0) {
                auto stamp = fs::last_write_time(p, ec);
                if (ec) {ec.clear();continue;}
                if (fs::file_time_type::clock::now() - stamp < std::chrono::hours(24 * minAgeDays)) continue;
            }
            add(p, category, "GREY", why, "", false);
            ++count;
        }
    };
    children(home / "Library/Developer/Xcode/DerivedData", "Xcode DerivedData",
             "Build artifact; verify no active Xcode builds or needed indexes", 120, 0);
    children(home / "Library/Logs", "User Logs",
             "User log; age alone does not prove safe ownership", 100, 30);
    children(home / "Downloads", "Old Downloads",
             "Old download; explicitly review file contents and destination", 80, 90);
    // The app can be gone while Ollama's models remain. Show the provider's
    // top-level data store as manual review, never automatically select it.
    add(home/".ollama", "Orphaned Ollama Data", "GREY",
        "Ollama models, logs, configuration and possibly keys; review before moving", "", false);
    const std::vector<std::pair<fs::path,string>> managed = {
        {home / ".npm", "npm"}, {home / ".cache/pip", "pip"},
        {home / ".cache/uv", "uv"}, {home / ".cache/huggingface/hub", "Hugging Face"},
        {home / ".ollama/models", "Ollama"}, {home / "Library/Caches/Homebrew", "Homebrew"},
        {home / "Library/Containers/com.docker.docker", "Docker"},
        {home / "Library/Application Support/LM Studio/models", "LM Studio"}
    };
    for (const auto& pair : managed) {
        add(pair.first, "Managed / Shared", "AMBER",
            pair.second + " manages or shares this storage; inventory only, use its own cleanup tools", "", false);
        if (!out.empty() && out.back().path == pair.first.lexically_normal()) out.back().cleanup = "none";
    }
    return out;
}

static string escapeJSON(const string& s) {
    string out="\"";
    constexpr char hex[]="0123456789abcdef";
    for(unsigned char ch:s) {
        switch(ch) {
            case '"':out+="\\\"";break;
            case '\\':out+="\\\\";break;
            case '\n':out+="\\n";break;
            case '\r':out+="\\r";break;
            case '\t':out+="\\t";break;
            default:if(ch<0x20) {out+="\\u00";out+=hex[ch>>4];out+=hex[ch&15];} else out+=(char)ch;
        }
    }
    return out+'"';
}
static void printJSON(const Entry& e) {
    const auto str=[&](const char* key,const string& val) {std::cout<<'"'<<key<<"\":"<<escapeJSON(val)<<',';};
    std::cout<<'{';
    str("type",e.type);str("id",e.path.string());str("name",e.path.extension()==".app"?e.path.stem().string():e.path.filename().string());
    str("path",e.path.string());str("category",e.category);str("status",e.status);
    str("confidence",e.confidence);str("reason",e.reason);str("cleanup",e.cleanup);
    str("bundle_id",e.bundleID);
    std::cout<<"\"eligible\":"<<(e.eligible?"true":"false")<<',';
    std::cout<<"\"size_bytes\":"<<(e.size.complete?std::to_string(e.size.bytes):"null")<<',';
    std::cout<<"\"file_count\":"<<(e.size.complete?std::to_string(e.size.files):"null")<<',';
    std::cout<<"\"dev\":"<<e.snapshot.device<<','<<"\"inode\":"<<e.snapshot.inode<<',';
    std::cout<<"\"mtime_sec\":"<<e.snapshot.mtime<<"}\n";
}
static void printHuman(const Entry& e) {
    std::cout<<'['<<e.status<<"] "<<e.category<<" | "<<e.path.filename().string()
      <<"\n  "<<e.path<<"\n  "<<e.reason<<" | "<<(e.eligible?"Eligible":"Review/blocked");
    if(e.size.complete) std::cout<<" | "<<e.size.bytes<<" bytes";
    std::cout<<'\n';
}
static void usage() {
    std::cout<<"StorageKit v5 (scanner only; cannot delete)\n"
      <<"  storagekit-scanner list [--jsonl] [--sizes] [--include-apple]\n"
      <<"  storagekit-scanner inventory [--jsonl] [--sizes]\n"
      <<"  storagekit-scanner storage [--jsonl] [--sizes]\n"
      <<"  storagekit-scanner scan --path <exact .app path> [--jsonl] [--sizes]\n"
      <<"  storagekit-scanner scan <exact name or bundle ID> [--jsonl] [--sizes]\n"
      <<"  --home /path --apps-root /path  (scanner fixture/testing only)\n";
}
int main(int argc,char** argv) {
    const char* envHome=std::getenv("HOME");
    if(!envHome) {std::cerr<<"HOME not set\n";return 2;}
    fs::path home=envHome, fixtureRoot;
    bool sizes=false,json=false,includeApple=false;
    string cmd,query,exactPath;
    for(int i=1;i<argc;i++) {
        string arg=argv[i];
        if(arg=="--jsonl")json=true;
        else if(arg=="--sizes")sizes=true;
        else if(arg=="--no-color"){} // retained CLI compatibility
        else if(arg=="--include-apple")includeApple=true;
        else if((arg=="--home"||arg=="--apps-root"||arg=="--path") && i+1<argc) {
            string val=argv[++i];
            if(arg=="--home")home=val;
            else if(arg=="--apps-root")fixtureRoot=val;
            else exactPath=val;
        } else if(cmd.empty())cmd=arg;
        else if(query.empty())query=arg;
        else {std::cerr<<"Unknown argument: "<<arg<<"\n";return 2;}
    }
    if(cmd!="list"&&cmd!="scan"&&cmd!="inventory"&&cmd!="storage") {usage();return 2;}
    std::vector<Entry> results;
    if(cmd=="inventory")results=inventory(home,sizes);
    else {
        std::vector<App> apps;
        if(!fixtureRoot.empty()) enumerateApps(fixtureRoot,apps);
        else {
            enumerateApps("/Applications",apps);
            enumerateApps(home/"Applications",apps);
            // Avoid expensive system app enumeration unless the user chooses
            // to show Apple apps. Apple app bundles remain non-removable.
            if(includeApple) enumerateApps("/System/Applications",apps);
        }
        std::set<string> seen;
        std::vector<App> unique;
        for(auto& a:apps) if(seen.insert(a.path.string()).second)unique.push_back(std::move(a));
        std::sort(unique.begin(),unique.end(),[](const App& a,const App& b){return lower(a.name)<lower(b.name);});
        if(cmd=="storage") {
            results=storageCandidates(home,sizes,unique);
        } else if(cmd=="list") {
            for(const auto& a:unique) {
                if(appleID(a.bundleID) && !includeApple) continue;
                const bool protectedBundle=protectedPath(a.path);
                const bool apple=appleID(a.bundleID);
                const bool verified=!protectedBundle&&!apple&&!a.bundleID.empty()&&safeAppLocation(a.path,home);
                auto e=entry(a.path,"app","Application",protectedBundle?"RED":apple?"AMBER":verified?"GREEN":"GREY",
                             verified?"high":"review",a.bundleID.empty()?"Bundle ID missing":a.bundleID,
                             "app",verified,a.bundleID,sizes);
                results.push_back(std::move(e));
            }
        } else {
            std::vector<App> found;
            for(const auto& a:unique) if(!exactPath.empty()?a.path.lexically_normal()==fs::path(exactPath).lexically_normal():
                 (!query.empty()&&(lower(a.name)==lower(query)||lower(a.bundleID)==lower(query)))) found.push_back(a);
            if(found.size()!=1) {std::cerr<<"Expected one exact app match; found "<<found.size()<<". Select an exact installed bundle path.\n";return 1;}
            results=discoverApp(found.front(),home,sizes);
        }
    }
    for(const auto& e:results) {if(json) printJSON(e);else printHuman(e);}
    return 0;
}

//
//  Ace.mm  —  王牌战争 ESP 实现
//
//  数据来源：Il2CppDump of Assembly-CSharp
//  内核原语：lara/kexploit/darksword
//  跨进程调用：lara/kexploit/TaskRop/RemoteCall
//

#import "Ace.h"
#import <objc/runtime.h>
#import <dlfcn.h>

#import "../kexploit/darksword.h"
#import "../kexploit/utils.h"
#import "../kexploit/TaskRop/RemoteCall.h"

#pragma mark - 偏移表（游戏更新只需改这一段）

#define AC_ASSEMBLY            "Assembly-CSharp"
#define AC_CORE_ASSEMBLY       "UnityEngine.CoreModule"
#define AC_CLASS_BATTLE        "Battle"

#define OFF_BATTLE_INS          0x88
#define OFF_BATTLE_CAMERA       0x28
#define OFF_BATTLE_PLAYERS      0x58
#define OFF_VTPC_CAMERA         0x68

#define OFF_OPC_INFO            0x3F0
#define OFF_OPC_WORLDPOS        0x43C
#define OFF_OPC_ISVIRTUAL       0x41F

#define OFF_PI_STATUS           0x10
#define OFF_PI_ROLEID           0x18
#define OFF_PI_NAME             0x28
#define OFF_PI_GROUPID          0x3C
#define OFF_PI_HP               0x64
#define OFF_PI_HPMAX            0x68

#define OFF_DICT_ENTRIES        0x18
#define OFF_DICT_COUNT          0x20
#define DICT_ENTRY_SIZE         0x18
#define DICT_ENTRY_VALUE        0x10

#define OFF_STR_LEN             0x10
#define OFF_STR_CHARS           0x14

#define AC_ST_DIE               11
#define AC_RTLD_DEFAULT         ((uint64_t)-2)

#pragma mark - 内嵌 overlay 页面（横屏 Canvas）

static const char *kAceHTML = R"ACEHTML(<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<style>
 html,body{margin:0;padding:0;width:100vw;height:100vh;overflow:hidden;background:transparent;
           -webkit-user-select:none;-webkit-touch-callout:none}
 canvas{position:fixed;inset:0;pointer-events:none}
</style>
</head>
<body>
<canvas id="c"></canvas>
<script>
var items = [];
var cv = document.getElementById('c');
var ctx = cv.getContext('2d');
function fit() {
  var dpr = window.devicePixelRatio || 1;
  var w = window.innerWidth, h = window.innerHeight;
  cv.width = w * dpr; cv.height = h * dpr;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}
fit();
window.addEventListener('resize', fit);
function draw() {
  ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
  for (var i = 0; i < items.length; i++) {
    var e = items[i];
    if (!e.v) continue;
    var w = e.w, h = e.h;
    if (w <= 0 || h <= 0) continue;
    ctx.strokeStyle = e.tm ? '#4ade80' : '#ff4d4d';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(e.x, e.y, w, h);
    var pct = e.mx > 0 ? Math.max(0, Math.min(1, e.hp / e.mx)) : 0;
    ctx.fillStyle = 'rgba(0,0,0,0.65)';
    ctx.fillRect(e.x, e.y - 8, w, 4);
    ctx.fillStyle = pct > 0.5 ? '#4ade80' : (pct > 0.25 ? '#facc15' : '#ef4444');
    ctx.fillRect(e.x, e.y - 8, w * pct, 4);
    var label = e.n + '  ' + e.d + 'm';
    ctx.font = '12px -apple-system,Helvetica';
    ctx.textAlign = 'center';
    ctx.lineWidth = 3;
    ctx.strokeStyle = 'rgba(0,0,0,0.85)';
    ctx.strokeText(label, e.x + w / 2, e.y - 13);
    ctx.fillStyle = e.tm ? '#4ade80' : '#ffffff';
    ctx.fillText(label, e.x + w / 2, e.y - 13);
  }
  requestAnimationFrame(draw);
}
draw();
window.aceUpdate = function (arr) { items = arr || []; };
window.aceClear  = function () { items = []; };
</script>
</body>
</html>)ACEHTML";

#pragma mark - 跨进程 ObjC 封装

@interface AceRemote : NSObject
@property (nonatomic, readonly) RemoteCall *rc;
- (BOOL)attach:(NSString *)processName;
- (uint64_t)callRaw:(uint64_t)fn args:(uint64_t *)args count:(NSUInteger)count;
- (uint64_t)allocString:(const char *)s;
- (void)freeRemote:(uint64_t)p;
- (uint64_t)sel:(const char *)name;
- (uint64_t)remoteClass:(const char *)name;
- (uint64_t)msg:(uint64_t)obj sel:(const char *)name;
- (uint64_t)msg:(uint64_t)obj sel:(const char *)name a0:(uint64_t)a0;
- (uint64_t)msg:(uint64_t)obj sel:(const char *)name a0:(uint64_t)a0 a1:(uint64_t)a1;
- (uint64_t)msg:(uint64_t)obj sel:(const char *)name rect:(CGRect)rect;
- (uint64_t)str:(const char *)s;
- (uint64_t)scratch;
@end

@implementation AceRemote {
    RemoteCall *_rc;
    uint64_t    _scratch;
    uint64_t    _rectBuf;
    NSMutableDictionary<NSString *, NSNumber *> *_selCache;
}

// libsystem / libdyld / QuartzCore 都在 dyld shared cache 里，全设备统一映射，
// 所以本进程解析出的地址在目标进程同样有效。
static uint64_t ac_sym(const char *name) { return (uint64_t)dlsym(RTLD_DEFAULT, name); }

- (instancetype)init {
    if ((self = [super init])) { _selCache = [NSMutableDictionary dictionary]; }
    return self;
}
- (RemoteCall *)rc { return _rc; }
- (uint64_t)scratch { return _scratch; }

- (BOOL)attach:(NSString *)processName {
    if (!ds_is_ready()) return NO;
    _rc = [[RemoteCall alloc] initWithProcess:processName useMigFilterBypass:YES];
    if (!_rc) return NO;

    uint64_t n = 0x1000;
    _scratch = [self callRaw:ac_sym("malloc") args:&n count:1];
    if (!_scratch) return NO;
    n = 0x100;
    _rectBuf = [self callRaw:ac_sym("malloc") args:&n count:1];
    return _rectBuf != 0;
}

- (uint64_t)callRaw:(uint64_t)fn args:(uint64_t *)args count:(NSUInteger)count {
    if (!_rc || !fn) return 0;
    return [_rc doRemoteCallStableWithTimeout:5000
                                 functionName:(char *)"ace"
                              functionPointer:(void *)fn
                                         args:args
                                     argCount:count];
}

- (uint64_t)allocString:(const char *)s {
    if (!s) return 0;
    uint64_t n = strlen(s) + 1;
    uint64_t buf = [self callRaw:ac_sym("malloc") args:&n count:1];
    if (!buf) return 0;
    if (![_rc remote_write:buf string:s]) return 0;
    return buf;
}

- (void)freeRemote:(uint64_t)p {
    if (!p) return;
    uint64_t a[1] = { p };
    [self callRaw:ac_sym("free") args:a count:1];
}

- (uint64_t)sel:(const char *)name {
    if (!name) return 0;
    NSString *key = @(name);
    NSNumber *hit = _selCache[key];
    if (hit) return hit.unsignedLongLongValue;

    uint64_t cstr = [self allocString:name];
    if (!cstr) return 0;
    uint64_t a[1] = { cstr };
    uint64_t s = [self callRaw:ac_sym("sel_registerName") args:a count:1];
    [self freeRemote:cstr];
    if (s) _selCache[key] = @(s);
    return s;
}

- (uint64_t)remoteClass:(const char *)name {
    uint64_t buf = [self allocString:name];
    if (!buf) return 0;
    uint64_t a[1] = { buf };
    uint64_t cls = [self callRaw:ac_sym("objc_getClass") args:a count:1];
    [self freeRemote:buf];
    return cls;
}

- (uint64_t)msg:(uint64_t)obj sel:(const char *)name {
    if (!obj) return 0;
    uint64_t a[2] = { obj, [self sel:name] };
    return [self callRaw:ac_sym("objc_msgSend") args:a count:2];
}
- (uint64_t)msg:(uint64_t)obj sel:(const char *)name a0:(uint64_t)a0 {
    if (!obj) return 0;
    uint64_t a[3] = { obj, [self sel:name], a0 };
    return [self callRaw:ac_sym("objc_msgSend") args:a count:3];
}
- (uint64_t)msg:(uint64_t)obj sel:(const char *)name a0:(uint64_t)a0 a1:(uint64_t)a1 {
    if (!obj) return 0;
    uint64_t a[4] = { obj, [self sel:name], a0, a1 };
    return [self callRaw:ac_sym("objc_msgSend") args:a count:4];
}

// CGRect 走浮点寄存器 d0-d3，线程状态改不到。
// 借 CAMetalDrawable 的 dirtyRect 实现（机器码为
//   ldp d0,d1,[x0,#0x20]; ldp d2,d3,[x0,#0x30]; ret）
// 把数据灌进 d0-d3，随后立刻发消息。
- (uint64_t)msg:(uint64_t)obj sel:(const char *)name rect:(CGRect)rect {
    if (!obj || !_rectBuf) return 0;
    if (![_rc remote_write:_rectBuf from:&rect size:sizeof(rect)]) return 0;

    static void *spillImp = NULL;
    if (!spillImp) {
        Class cls = NSClassFromString(@"CAMetalDrawable");
        if (!cls) return 0;
        Method m = class_getInstanceMethod(cls, @selector(dirtyRect));
        if (!m) return 0;
        spillImp = method_getImplementation(m);
    }
    uint64_t a1[1] = { _rectBuf - 0x20 };
    [self callRaw:(uint64_t)spillImp args:a1 count:1];

    uint64_t a2[2] = { obj, [self sel:name] };
    return [self callRaw:ac_sym("objc_msgSend") args:a2 count:2];
}

- (uint64_t)str:(const char *)s {
    if (!s) return 0;
    uint64_t cstr = [self allocString:s];
    if (!cstr) return 0;
    uint64_t cls = [self remoteClass:"NSString"];
    if (!cls) { [self freeRemote:cstr]; return 0; }
    uint64_t a[4] = { cls, [self sel:"stringWithCString:encoding:"], cstr, 4 };
    uint64_t out = [self callRaw:ac_sym("objc_msgSend") args:a count:4];
    [self freeRemote:cstr];
    return out;
}
@end

#pragma mark - AceESP

@implementation AceESP {
    AceRemote *_r;
    uint64_t _battle, _cameraObj;
    CGSize   _screen;
    uint64_t _win, _webView;
    dispatch_source_t _timer;

    // il2cpp 导出（都在目标进程里）
    uint64_t _fnDomainGet, _fnAsmOpen, _fnAsmImage, _fnClassFromName;
    uint64_t _fnFieldFromName, _fnFieldStaticGet;
    uint64_t _fnMethodFromName, _fnInvoke, _fnUnbox;

    uint64_t _mWorldToScreen;   // MethodInfo* of Camera.WorldToScreenPoint
    uint64_t _mGetTransform;    // MethodInfo* of Component.get_transform
    uint64_t _mGetPosition;     // MethodInfo* of Transform.get_position
    uint64_t _camClass, _transformClass;
}

+ (instancetype)shared {
    static AceESP *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[AceESP alloc] init]; });
    return inst;
}

- (instancetype)init {
    if ((self = [super init])) {
        _targetProcess = @"AceForce";   // ← 用 lara 的进程列表确认真实名字
        _screen = CGSizeMake(0, 0);
    }
    return self;
}

- (void)log:(NSString *)fmt, ... {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[ACE] %@", s);
    void (^b)(NSString *) = self.logBlock;
    if (b) { dispatch_async(dispatch_get_main_queue(), ^{ b(s); }); }
}

#pragma mark 读取原语（经 RemoteCall 读目标进程虚拟地址）

- (uint64_t)rd64:(uint64_t)addr {
    if (!addr) return 0;
    return [_r.rc remoteRead64From:addr];
}
- (uint32_t)rd32:(uint64_t)addr { return (uint32_t)([self rd64:addr] & 0xFFFFFFFF); }
- (int32_t)rdi32:(uint64_t)addr  { return (int32_t)([self rd64:addr] & 0xFFFFFFFF); }
- (float)rdf:(uint64_t)addr {
    uint32_t bits = [self rd32:addr];
    float f; memcpy(&f, &bits, 4); return f;
}
- (uint8_t)rd8:(uint64_t)addr { return (uint8_t)([self rd64:addr] & 0xFF); }

- (void)rdName:(uint64_t)strObj into:(char *)dst size:(size_t)n {
    dst[0] = 0;
    if (!strObj) return;
    int32_t len = [self rdi32:strObj + OFF_STR_LEN];
    if (len <= 0 || len > 64) return;
    if ((size_t)len >= n) len = (int32_t)n - 1;

    uint16_t buf[65] = {0};
    if (![_r.rc remoteRead:strObj + OFF_STR_CHARS to:buf size:(uint64_t)len * 2]) return;
    NSString *s = [[NSString alloc] initWithCharacters:buf length:len];
    if (s) strncpy(dst, s.UTF8String, n - 1);
}

#pragma mark il2cpp

- (uint64_t)remoteDlsym:(const char *)sym {
    uint64_t buf = [_r allocString:sym];
    if (!buf) return 0;
    uint64_t a[2] = { AC_RTLD_DEFAULT, buf };
    uint64_t fn = [_r callRaw:(uint64_t)dlsym(RTLD_DEFAULT, "dlsym") args:a count:2];
    [_r freeRemote:buf];
    return fn;
}

- (BOOL)resolveIl2Cpp {
    struct { const char *n; uint64_t *s; } t[] = {
        { "il2cpp_domain_get",                &_fnDomainGet },
        { "il2cpp_domain_assembly_open",      &_fnAsmOpen },
        { "il2cpp_assembly_get_image",        &_fnAsmImage },
        { "il2cpp_class_from_name",           &_fnClassFromName },
        { "il2cpp_class_get_field_from_name", &_fnFieldFromName },
        { "il2cpp_field_static_get_value",    &_fnFieldStaticGet },
        { "il2cpp_class_get_method_from_name",&_fnMethodFromName },
        { "il2cpp_runtime_invoke",            &_fnInvoke },
    };
    for (size_t i = 0; i < sizeof(t) / sizeof(t[0]); i++) {
        uint64_t a = [self remoteDlsym:t[i].n];
        if (!a) { [self log:@"il2cpp 符号缺失: %s", t[i].n]; return NO; }
        *t[i].s = a;
    }
    [self log:@"il2cpp API 解析完成"];
    return YES;
}

- (uint64_t)classIn:(const char *)asmName ns:(const char *)ns name:(const char *)clsName {
    uint64_t dom = [_r callRaw:_fnDomainGet args:NULL count:0];
    if (!dom) return 0;

    uint64_t asmBuf = [_r allocString:asmName];
    uint64_t a1[2] = { dom, asmBuf };
    uint64_t asm_ = [_r callRaw:_fnAsmOpen args:a1 count:2];
    [_r freeRemote:asmBuf];
    if (!asm_) { [self log:@"找不到程序集 %s", asmName]; return 0; }

    uint64_t a2[1] = { asm_ };
    uint64_t image = [_r callRaw:_fnAsmImage args:a2 count:1];

    uint64_t nsBuf = [_r allocString:ns];
    uint64_t nmBuf = [_r allocString:clsName];
    uint64_t a3[3] = { image, nsBuf, nmBuf };
    uint64_t klass = [_r callRaw:_fnClassFromName args:a3 count:3];
    [_r freeRemote:nsBuf];
    [_r freeRemote:nmBuf];

    if (!klass) [self log:@"找不到类 %s::%s", ns, clsName];
    return klass;
}

- (uint64_t)staticField:(uint64_t)klass name:(const char *)fname {
    uint64_t fb = [_r allocString:fname];
    uint64_t a[2] = { klass, fb };
    uint64_t field = [_r callRaw:_fnFieldFromName args:a count:2];
    [_r freeRemote:fb];
    if (!field) return 0;

    uint64_t out = [_r scratch] + 0x100;
    uint64_t a2[2] = { field, out };
    [_r callRaw:_fnFieldStaticGet args:a2 count:2];
    return [self rd64:out];
}

- (uint64_t)method:(const char *)mname inClass:(uint64_t)klass argc:(int)argc {
    uint64_t mb = [_r allocString:mname];
    uint64_t a[3] = { klass, mb, (uint64_t)argc };
    uint64_t m = [_r callRaw:_fnMethodFromName args:a count:3];
    [_r freeRemote:mb];
    return m;
}

- (BOOL)resolveBattle {
    uint64_t klass = [self classIn:AC_ASSEMBLY ns:"" name:AC_CLASS_BATTLE];
    if (!klass) return NO;

    _battle = [self staticField:klass name:"Ins"];
    if (!_battle) { [self log:@"Battle.Ins 为空（可能还没进对局）"]; return NO; }
    [self log:@"Battle.Ins = 0x%llx", _battle];

    // 相机
    uint64_t vtpc = [self rd64:_battle + OFF_BATTLE_CAMERA];
    _cameraObj = vtpc ? [self rd64:vtpc + OFF_VTPC_CAMERA] : 0;
    if (!_cameraObj) { [self log:@"相机对象为空（可稍后重试）"]; return YES; }

    _camClass = [self classIn:AC_CORE_ASSEMBLY ns:"UnityEngine" name:"Camera"];
    _transformClass = [self classIn:AC_CORE_ASSEMBLY ns:"UnityEngine" name:"Transform"];
    if (_camClass)       _mWorldToScreen = [self method:"WorldToScreenPoint" inClass:_camClass argc:1];
    if (_camClass)       _mGetTransform  = [self method:"get_transform"      inClass:_camClass argc:0];
    if (_transformClass) _mGetPosition   = [self method:"get_position"       inClass:_transformClass argc:0];

    [self log:@"相机 0x%llx  WorldToScreen=%d get_transform=%d get_position=%d",
          _cameraObj, _mWorldToScreen != 0, _mGetTransform != 0, _mGetPosition != 0];
    return YES;
}

// 通用 invoke：参数走内存，绕开浮点寄存器 ABI
- (uint64_t)invoke:(uint64_t)methodInfo obj:(uint64_t)obj count:(int)count value:(void *)value {
    if (!methodInfo || !obj) return 0;

    uint64_t paramsBuf = [_r scratch] + 0x300;
    uint64_t excBuf    = [_r scratch] + 0x200;
    uint64_t argBuf    = [_r scratch] + 0x000;

    uint64_t zero = 0;
    [_r.rc remote_write:excBuf from:&zero size:8];

    uint64_t ptrArr[1] = { argBuf };
    if (count > 0 && value) {
        [_r.rc remote_write:argBuf from:value size:16];
    }
    [_r.rc remote_write:paramsBuf from:ptrArr size:8];

    uint64_t a[4] = { methodInfo, obj, count > 0 ? paramsBuf : 0, excBuf };
    return [_r callRaw:_fnInvoke args:a count:4];
}

- (BOOL)worldToScreen:(float[3])w out:(float[3])scr {
    if (!_mWorldToScreen || !_cameraObj) return NO;
    uint64_t boxed = [self invoke:_mWorldToScreen obj:_cameraObj count:1 value:w];
    if (!boxed) return NO;
    float v[3] = {0};
    if (![_r.rc remoteRead:boxed + 0x10 to:v size:12]) return NO;
    scr[0] = v[0]; scr[1] = v[1]; scr[2] = v[2];
    return YES;
}

- (BOOL)selfPosition:(float[3])out {
    if (!_mGetTransform || !_mGetPosition || !_cameraObj) return NO;
    uint64_t trans = [self invoke:_mGetTransform obj:_cameraObj count:0 value:NULL];
    if (!trans) return NO;
    uint64_t boxed = [self invoke:_mGetPosition obj:trans count:0 value:NULL];
    if (!boxed) return NO;
    float v[3] = {0};
    if (![_r.rc remoteRead:boxed + 0x10 to:v size:12]) return NO;
    out[0] = v[0]; out[1] = v[1]; out[2] = v[2];
    return YES;
}

#pragma mark 扫描

- (int)scanInto:(NSMutableArray *)out selfPos:(float[3])me {
    if (!_battle) return 0;
    uint64_t dict = [self rd64:_battle + OFF_BATTLE_PLAYERS];
    if (!dict) return 0;

    uint64_t entries = [self rd64:dict + OFF_DICT_ENTRIES];
    int32_t  count   = [self rdi32:dict + OFF_DICT_COUNT];
    if (!entries || count <= 0 || count > 4096) return 0;

    int added = 0;
    for (int i = 0; i < count; i++) {
        uint64_t e = entries + (uint64_t)i * DICT_ENTRY_SIZE;
        int32_t hc = [self rdi32:e];
        if (hc < 0) continue;

        uint64_t opc = [self rd64:e + DICT_ENTRY_VALUE];
        if (!opc) continue;
        if ([self rd8:opc + OFF_OPC_ISVIRTUAL]) continue;

        uint64_t info = [self rd64:opc + OFF_OPC_INFO];
        if (!info) continue;

        uint8_t st = [self rd8:info + OFF_PI_STATUS];
        if (st == AC_ST_DIE) continue;

        float w[3];
        if (![_r.rc remoteRead:opc + OFF_OPC_WORLDPOS to:w size:12]) continue;

        float scr[3];
        if (![self worldToScreen:w out:scr]) continue;
        if (scr[0] == 0 && scr[1] == 0) continue;
        if (scr[2] < 0.1f) continue;                       // 在相机背后

        char name[64];
        [self rdName:[self rd64:info + OFF_PI_NAME] into:name size:sizeof(name)];

        float dx = w[0] - me[0], dy = w[1] - me[1], dz = w[2] - me[2];
        int dist = (int)sqrtf(dx*dx + dy*dy + dz*dz);

        int32_t hp  = [self rdi32:info + OFF_PI_HP];
        int32_t mx  = [self rdi32:info + OFF_PI_HPMAX];
        int32_t grp = [self rdi32:info + OFF_PI_GROUPID];

        // 框的尺寸：先按距离反比估，够用
        float bh = (dist > 0) ? (1400.0f / (float)dist) : 200.0f;
        if (bh > 400) bh = 400;
        float bw = bh * 0.45f;

        [out addObject:@{
            @"v":  @1,
            @"x":  @(scr[0] - bw / 2),
            @"y":  @(_screen.height - scr[1] - bh / 2),
            @"w":  @(bw),
            @"h":  @(bh),
            @"n":  @(name[0] ? name : "?"),
            @"d":  @(dist),
            @"hp": @(hp),
            @"mx": @(mx),
            @"tm": @(0),               // 队友判定需要本地 groupId，待接入
            @"st": @(st),
            @"grp":@(grp),
        }];
        added++;
    }
    return added;
}

#pragma mark overlay

- (uint64_t)findGameWindow {
    uint64_t appCls = [_r remoteClass:"UIApplication"];
    if (!appCls) return 0;
    uint64_t app = [_r msg:appCls sel:"sharedApplication"];
    if (!app) return 0;

    uint64_t scenes = [_r msg:app sel:"connectedScenes"];
    uint64_t arr    = scenes ? [_r msg:scenes sel:"allObjects"] : 0;
    uint64_t n      = arr ? [_r msg:arr sel:"count"] : 0;

    for (uint64_t i = 0; i < n; i++) {
        uint64_t scene = [_r msg:arr sel:"objectAtIndex:" a0:i];
        if (!scene) continue;
        uint64_t wins = [_r msg:scene sel:"windows"];
        uint64_t wn   = wins ? [_r msg:wins sel:"count"] : 0;
        for (uint64_t j = 0; j < wn; j++) {
            uint64_t w = [_r msg:wins sel:"objectAtIndex:" a0:j];
            if (!w) continue;
            if ([_r msg:w sel:"isHidden"]) continue;
            return w;
        }
    }
    return [_r msg:app sel:"keyWindow"];
}

- (BOOL)installOverlay {
    _win = [self findGameWindow];
    if (!_win) { [self log:@"没找到游戏窗口（overlay 跳过）"]; return NO; }

    // bounds 是 CGRect，用 remote_getCGRect 的思路自己读
    uint64_t wvCls = [_r remoteClass:"WKWebView"];
    if (!wvCls) { [self log:@"WKWebView 不可用"]; return NO; }

    // 先用屏幕尺寸兜底
    CGRect b = [UIScreen mainScreen].bounds;
    _screen = b.size;

    uint64_t wv = [_r msg:wvCls sel:"alloc"];
    if (!wv) { [self log:@"WKWebView alloc 失败"]; return NO; }

    [_r msg:wv sel:"initWithFrame:" rect:b];
    [_r msg:wv sel:"setUserInteractionEnabled:" a0:0];
    [_r msg:wv sel:"setOpaque:" a0:0];
    uint64_t clear = [_r msg:[_r remoteClass:"UIColor"] sel:"clearColor"];
    [_r msg:wv sel:"setBackgroundColor:" a0:clear];

    uint64_t html = [_r str:kAceHTML];
    uint64_t base = [_r str:"about:blank"];
    [_r msg:wv sel:"loadHTMLString:baseURL:" a0:html a1:base];

    [_r msg:_win sel:"addSubview:" a0:wv];
    [_r msg:_win sel:"bringSubviewToFront:" a0:wv];

    _webView = wv;
    [self log:@"overlay 已挂载 webview=0x%llx win=0x%llx", wv, _win];
    return YES;
}

- (void)push:(NSArray *)items {
    if (!_webView) return;
    NSData *d = [NSJSONSerialization dataWithJSONObject:items options:0 error:nil];
    if (!d) return;
    NSString *js = [NSString stringWithFormat:@"window.aceUpdate(%@);",
                    [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]];
    uint64_t rjs = [_r str:js.UTF8String];
    [_r msg:_webView sel:"evaluateJavaScript:completionHandler:" a0:rjs a1:0];
}

#pragma mark 主循环

- (void)tick {
    if (!_r) return;

    // Battle.Ins 可能在对局切换时变化，定期刷新
    if (!_battle || !_cameraObj) {
        uint64_t k = [self classIn:AC_ASSEMBLY ns:"" name:AC_CLASS_BATTLE];
        if (k) {
            _battle = [self staticField:k name:"Ins"];
            if (_battle) {
                uint64_t vtpc = [self rd64:_battle + OFF_BATTLE_CAMERA];
                _cameraObj = vtpc ? [self rd64:vtpc + OFF_VTPC_CAMERA] : 0;
                [self log:@"Battle=0x%llx camera=0x%llx", _battle, _cameraObj];
            }
        }
        if (!_battle) return;
    }

    float me[3] = {0};
    [self selfPosition:me];

    NSMutableArray *items = [NSMutableArray array];
    int n = [self scanInto:items selfPos:me];
    self.lastPlayerCount = (NSUInteger)n;

    if (n > 0) [self push:items];
}

- (void)startLoop {
    if (_timer) return;
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                    dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    uint64_t interval = 100ull * NSEC_PER_MSEC;   // 10Hz，别调太高
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, interval, 20ull * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(_timer, ^{ [self tick]; });
    dispatch_resume(_timer);
}

#pragma mark 生命周期

- (BOOL)start {
    if (_running) { [self log:@"已经在跑了"]; return YES; }

    if (!ds_is_ready()) {
        [self log:@"内核 rw 未就绪：请先确认 lara 的 kexploit 已跑过（ds_run）"];
        return NO;
    }
    [self log:@"内核 rw 就绪，base=0x%llx", ds_get_kernel_base()];

    _r = [[AceRemote alloc] init];
    if (![_r attach:_targetProcess]) {
        [self log:@"连接进程 %@ 失败（进程名对不对？游戏在前台吗？）", _targetProcess];
        _r = nil;
        return NO;
    }
    [self log:@"已连接 %@", _targetProcess];

    if (![self resolveIl2Cpp]) { _r = nil; return NO; }

    if (![self resolveBattle]) {
        [self log:@"Battle 未就绪，仍会后台重试"];
    }

    if (![self installOverlay]) {
        [self log:@"overlay 未装上，但数据扫描继续进行（看日志）"];
    }

    [self startLoop];
    _running = YES;
    return YES;
}

- (void)stop {
    if (_timer) { dispatch_source_cancel(_timer); _timer = nil; }
    _running = NO;
    _battle = _cameraObj = _win = _webView = 0;
    _r = nil;
    [self log:@"已停止"];
}

@end

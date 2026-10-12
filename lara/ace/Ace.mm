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

#define OFF_BATTLE_INS          0x88   // static Battle Ins
#define OFF_BATTLE_CAMERA       0x28   // vThirdPersonCamera*
#define OFF_BATTLE_PLAYERS      0x58   // Dictionary<long, OtherPlayerController*>

#define OFF_VTPC_CAMERA         0x68   // UnityEngine.Camera*

#define OFF_OPC_INFO            0x3F0  // PlayerInfo*
#define OFF_OPC_WORLDPOS        0x43C  // Vector3 (inline, 12 bytes)
#define OFF_OPC_ISVIRTUAL       0x41F  // bool

#define OFF_PI_STATUS           0x10   // byte
#define OFF_PI_ROLEID           0x18   // int64
#define OFF_PI_NAME             0x28   // string*
#define OFF_PI_GROUPID          0x3C   // int32
#define OFF_PI_HP               0x64   // int32
#define OFF_PI_HPMAX            0x68   // int32

#define OFF_DICT_ENTRIES        0x18   // Entry*
#define OFF_DICT_COUNT          0x20   // int32
#define DICT_ENTRY_SIZE         0x18
#define DICT_ENTRY_VALUE        0x10

#define OFF_STR_LEN             0x10
#define OFF_STR_CHARS           0x14

#define AC_ST_DIE               11

#define AC_RTLD_DEFAULT         ((uint64_t)-2)

#pragma mark - 内嵌 overlay 页面（横屏，尺寸由宿主注入）

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
  cv.style.width = w + 'px'; cv.style.height = h + 'px';
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

    var col = e.tm ? '#4ade80' : '#ff4d4d';
    ctx.strokeStyle = col;
    ctx.lineWidth = 1.5;
    ctx.strokeRect(e.x, e.y, w, h);

    // 血条
    var pct = e.mx > 0 ? Math.max(0, Math.min(1, e.hp / e.mx)) : 0;
    ctx.fillStyle = 'rgba(0,0,0,0.65)';
    ctx.fillRect(e.x, e.y - 8, w, 4);
    ctx.fillStyle = pct > 0.5 ? '#4ade80' : (pct > 0.25 ? '#facc15' : '#ef4444');
    ctx.fillRect(e.x, e.y - 8, w * pct, 4);

    // 名字 + 距离
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
- (uint64_t)msg:(uint64_t)obj sel:(const char *)name;
- (uint64_t)msg:(uint64_t)obj sel:(const char *)name a0:(uint64_t)a0;
- (uint64_t)msg:(uint64_t)obj sel:(const char *)name a0:(uint64_t)a0 a1:(uint64_t)a1;
- (uint64_t)msg:(uint64_t)obj sel:(const char *)name rect:(CGRect)rect;
- (uint64_t)string:(const char *)s;
- (uint64_t)scratch;
- (void)deallocAll;
@end
)ACEHTML_PLACEHOLDER

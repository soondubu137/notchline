const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('Notchline/Notchline/Products/Trae/Companion/trae-renderer.js','utf8');
function reader(focused = true) {
  let Reader;
  const context = {HTMLElement:class {addEventListener(){}},customElements:{get:()=>null,define:(_tag,value)=>{Reader=value}},
    __notchlineTraeProjectionV1:require('../../Notchline/Notchline/Products/Trae/Companion/trae-projection.js'),
    window:{focus(){}},document:{hasFocus:()=>focused,visibilityState:'visible'},
    clearTimeout,clearInterval,setTimeout,setInterval,Date,Map,Set,JSON};
  vm.runInNewContext(source,context);
  const r=new Reader();r.stop();r.retained=new Set();r.emitted=[];r.emit=f=>r.emitted.push(f);
  r.environment=context;return r;
}
function row(status,requests=[],preview=null) { return {threadID:'000000000000000000000001',turnID:'000000000000000000000002',messageID:'000000000000000000000003',status,requests,preview}; }
function batch(r,baseline=false) {return {baseline,rows:[r],excluded:[],at:1};}
test('content coalescing preserves start, wait, resolution and end order',async()=>{
 const r=reader();r.running=true;r.validated.set(row().threadID,{folder:null});
 r.enqueue(batch(row('in_progress'),true));
 r.enqueue(batch(row('in_progress',[],'first')));
 r.enqueue(batch(row('in_progress',[],'second')));
 r.enqueue(batch(row('in_progress',[{id:'wait'}],'second')));
 r.enqueue(batch(row('in_progress',[],'third')));
 r.enqueue(batch(row('completed',[],'final')));
 await r.flush();
 assert.deepEqual(Array.from(r.emitted,x=>[x.sequence,x.rows[0].status,x.rows[0].requests.length,x.rows[0].preview]),
 [[1,'in_progress',0,null],[2,'in_progress',0,'second'],[3,'in_progress',1,'second'],[4,'in_progress',0,'third'],[5,'completed',0,'final']]);
});
test('retired asynchronous identity validation cannot publish into a new observation',async()=>{
 const r=reader();let resolve;r.api={chat:{getSession:()=>new Promise(done=>{resolve=done})}};
 r.pending.push(batch(row('in_progress'),true));const flushed=r.flush();r.stop();
 resolve({code:0,data:{chat_session_id:row().threadID,session_type:'side_chat'}});await flushed;
 assert.equal(r.emitted.length,0);assert.equal(r.validated.size,0);
});
test('queue overflow stops only this observer and reports unavailable',()=>{
 const r=reader();r.running=true;
 for(let i=0;i<129;i++)r.enqueue(batch(row('in_progress',[{id:String(i)}])));
 assert.equal(r.emitted.at(-1).type,'unavailable');assert.equal(r.pending.length,0);
});

test('exact navigation requires both native selection and the owning window focus',async()=>{
 for(const focused of [true,false]) {
  const r=reader(focused),id=row().threadID;r.validated.set(id,{folder:null});
  r.api={chat:{getSession:async()=>({code:0,data:{chat_session_id:id,session_type:'side_chat'}})}};
  r.v2={switchToSession:async()=>{},getCurrentSession:()=>({sessionId:id})};
  await r.handle({op:'navigate',threadID:id,requestId:'navigation'});
  assert.equal(r.emitted.at(-1).ok,focused);
 }
});
test('refused navigation never tears down the observer',async()=>{
 const r=reader();let stopped=false;r.unsubscribe=()=>{stopped=true};
 await r.handle({op:'navigate',threadID:row().threadID,requestId:'navigation'});
 assert.equal(r.emitted.at(-1).ok,false);assert.equal(stopped,false);
});

function completionReader() {
 const r=reader();r.unsubscribe=()=>{};r.platform=()=> 'trae-ide';
 const identity=row(),session={sessionId:identity.threadID,sessionType:'side_chat'};
 let message={sessionId:identity.threadID,turnId:identity.turnID,messageId:identity.messageID,status:'completed'};
 r.stores={eA:{allSessions:{get:()=>[session]},lastAgentMessage:{get:()=>message},planMode:{get:()=>false}}};
 r.v2={getCurrentSession:()=>session};r.permission={get:()=>null};r.questions={get:()=>null};
 r.nativeHost={windowId:1,getActiveWindowId:async()=>1,getWindowCountByState:async()=>({focused:1})};
 r.api={chat:{getSession:async()=>({code:0,data:{chat_session_id:identity.threadID,session_type:'side_chat'}})}};
 r.completionVisible=()=>true;
 return {r,setMessage:x=>{message={...message,...x}}};
}
test('read proof needs the native focused window, never just the last active ID',async()=>{
 const {r}=completionReader();assert.ok(await r.readCompletion());
 r.nativeHost.getActiveWindowId=async()=>2;assert.equal(await r.readCompletion(),null);
 r.nativeHost.getActiveWindowId=async()=>1;r.nativeHost.getWindowCountByState=async()=>({focused:0});
 assert.equal(await r.readCompletion(),null);
});
test('a second window can prove the same native completion without lifecycle ownership',async()=>{
 const {r}=completionReader();r.nativeHost.windowId=2;r.nativeHost.getActiveWindowId=async()=>2;
 assert.equal(r.validated.size,0);assert.equal((await r.readCompletion()).windowID,2);
 assert.equal(r.validated.size,0);assert.equal(r.last.size,0);
});
test('running, pending input, approval and invisible completion cannot produce read proof',async()=>{
 const {r,setMessage}=completionReader();setMessage({status:'in_progress'});assert.equal(await r.readCompletion(),null);
 setMessage({status:'completed'});r.questions.get=()=>({id:'question'});assert.equal(await r.readCompletion(),null);
 r.questions.get=()=>null;r.permission.get=()=>({id:'permission'});assert.equal(await r.readCompletion(),null);
 r.permission.get=()=>null;r.completionVisible=()=>false;assert.equal(await r.readCompletion(),null);
});
test('stop, focus change and a newer Turn during native validation invalidate a read',async()=>{
 for(const change of ['stop','focus','turn','scope','mutation']) {
  const {r,setMessage}=completionReader();let finish;
  r.api.chat.getSession=()=>new Promise(resolve=>{finish=resolve});
  const pending=r.readCompletion();while(!finish)await new Promise(resolve=>setImmediate(resolve));
  if(change==='stop')r.stop();
  if(change==='focus')r.nativeHost.getActiveWindowId=async()=>2;
  if(change==='turn')setMessage({turnId:'000000000000000000000009'});
  if(change==='scope')r.stores.eA.planMode.get=()=>true;
  if(change==='mutation')r.stores.eA.lastAgentMessage.get().turnId='000000000000000000000009';
  finish({code:0,data:{chat_session_id:row().threadID,session_type:'side_chat'}});
  assert.equal(await pending,null,change);
 }
});
test('failed optional read leaves lifecycle subscription alive',async()=>{
 const {r}=completionReader();r.nativeHost.getActiveWindowId=async()=>{throw Error('missing method')};
 await r.handle({op:'read',requestId:'read'});assert.equal(r.emitted.at(-1).reading,null);assert.ok(r.unsubscribe);
});

 test('completion visibility requires the exact root and visible unoccluded controls',()=>{
  const r=reader(),env=r.environment,id=row().messageID;
  const rect={left:20,right:120,top:50,bottom:80};
  const parent={parentElement:null,getBoundingClientRect:()=>({left:0,right:200,top:0,bottom:100})};
  const child={};const bar={parentElement:parent,checkVisibility:()=>true,getBoundingClientRect:()=>rect,contains:e=>e===child};
  const root={querySelector:selector=>{assert.equal(selector,'.assistant-action-bar');return bar;}};
  env.innerWidth=200;env.innerHeight=100;env.getComputedStyle=()=>({overflowX:'hidden',overflowY:'auto'});
  env.document.querySelectorAll=selector=>{assert.equal(selector,`.turn__agent-message[data-message-id="${id}"]`);return [root];};
  env.document.elementFromPoint=()=>child;
  assert.equal(r.completionVisible(id),true);
  rect.top=105;rect.bottom=135;assert.equal(r.completionVisible(id),false);
  rect.top=50;rect.bottom=80;parent.getBoundingClientRect=()=>({left:0,right:200,top:0,bottom:40});
  assert.equal(r.completionVisible(id),false);
  parent.getBoundingClientRect=()=>({left:0,right:200,top:0,bottom:100});
  env.document.elementFromPoint=()=>({});assert.equal(r.completionVisible(id),false);
  env.document.elementFromPoint=()=>bar;bar.checkVisibility=()=>false;assert.equal(r.completionVisible(id),false);
  bar.checkVisibility=()=>true;env.document.querySelectorAll=()=>[root,root];assert.equal(r.completionVisible(id),false);
  env.document.querySelectorAll=()=>[];assert.equal(r.completionVisible(id),false);
  assert.equal(r.completionVisible('invalid'),false);
 });

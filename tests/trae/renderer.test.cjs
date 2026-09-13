const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('Notchline/Notchline/Products/Trae/Companion/trae-renderer.js','utf8');
function reader(focused = true) {
  let Reader;
  const context = {HTMLElement:class {addEventListener(){}},customElements:{get:()=>null,define:(_tag,value)=>{Reader=value}},
    __notchlineTraeProjectionV1:{id:value=>/^[a-f0-9]{24}$/.test(value)},
    window:{focus(){}},document:{hasFocus:()=>focused},
    clearTimeout,clearInterval,setTimeout,setInterval,Date,Map,Set,JSON};
  vm.runInNewContext(source,context);
  const r=new Reader();r.stop();r.retained=new Set();r.emitted=[];r.emit=f=>r.emitted.push(f);
  return r;
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

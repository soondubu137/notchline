const {test} = require('node:test');
const assert = require('node:assert/strict');
const P = require('../../Notchline/Notchline/Products/Trae/Companion/trae-projection.js');
const id = n => n.toString(16).padStart(24, '0');
function fixture() {
  return {session:{sessionId:id(1),sessionType:'side_chat',name:'Native title'},
    message:{messageId:id(2),turnId:id(3),replyToMessageId:id(4),sessionId:id(1),status:'in_progress',agentId:'root',createdAt:1789275000},
    plan:{id:id(5),messageId:id(2),agentId:'root',agentRunId:'producer',parentAgentRunIds:[],hide:null,thought:'Displayed progress',
      reasoningContent:'NEVER EXPORT',confirmInfo:{confirm_status:'unconfirmed',auto_confirm:false},
      toolCallInfo:{id:id(6),name:'RunCommand',params:{command:'printf test',command_type:'short_running_process',requires_approval:true,blocking:true},result:{status:'running'}}},
    context:{platform:'trae-ide',permissionID:id(5),questionID:null,planMode:false,omitDetail:false,localize:(_k,_a,s)=>s}};
}
function project(f) { return P.project(f.session,f.message,[f.plan],f.context); }
test('native IDE fields may omit remote-only mode and env',()=>{
 const f=fixture(),row=project(f);assert.equal(row.preview,'Displayed progress');assert.equal(row.requests[0].command,'printf test');
 assert.equal(JSON.stringify(row).includes('NEVER EXPORT'),false);assert.equal(row.requests[0].producer,'producer');
});
test('root admission excludes child, remote, SOLO and Plan/Spec',()=>{
 for(const mutate of [f=>f.session.parentSessionId=id(9),f=>f.session.remoteProjectId='remote',f=>f.session.env='remote',f=>f.context.platform='lite',f=>f.context.planMode=true,f=>f.message.userMessageContext={is_in_spec_mode:true}]){
  const f=fixture();mutate(f);assert.equal(project(f),null);
 }
});
test('temporary assistant does not correlate a Turn',()=>{const f=fixture();delete f.message.turnId;assert.equal(project(f),null)});
test('other producer and hidden content do not replace root progress or requests',()=>{
 for(const mutate of [f=>f.plan.hide=true,f=>f.plan.parentAgentRunIds=['parent'],f=>f.plan.agentId='child']){
  const f=fixture();mutate(f);assert.equal(project(f).preview,null);assert.deepEqual(project(f).requests,[]);
 }
});
test('outer running result cannot reopen success, decline or cancellation',()=>{
 for(const result of ['success','failed','skipped','canceled']) { const f=fixture();f.plan.toolCallInfo.result.status=result;assert.deepEqual(project(f).requests,[]) }
 const f=fixture();f.message.status='canceled';f.message.chatEndTime=1789275010000;assert.equal(project(f).endedAt,1789275010);assert.deepEqual(project(f).requests,[]);
});
test('only positively selected manual confirmation opens approval',()=>{
 for(const mutate of [f=>f.context.permissionID=null,f=>f.plan.confirmInfo.auto_confirm=true,f=>f.plan.confirmInfo.auto_review_result={decision:'reviewing'}]){
  const f=fixture();mutate(f);assert.deepEqual(project(f).requests,[]);
 }
 const f=fixture();f.plan.confirmInfo.auto_review_result={decision:'reviewing',fallback_to_manual_confirmation:true};assert.equal(project(f).requests.length,1);
});
test('rich command permissions return to Trae without a partial command body',()=>{
 const f=fixture();f.plan.confirmInfo.sandbox_status='approval';assert.equal(project(f).requests[0].kind,'unsupported');
});
test('question sets retain order, labels, descriptions and distinct field limits',()=>{
 const f=fixture();f.plan.toolCallInfo.name='AskUserQuestion';f.context.permissionID=null;f.context.questionID=f.plan.id;
 f.plan.toolCallInfo.params={questions:[{header:'Colour',question:'Which colour?',options:[{label:'Blue',description:'Blue shade'}]},{header:'Shape',question:'Which shapes?',multiSelect:true,options:[{label:'Circle'}]}]};
 const qs=project(f).requests[0].questions;assert.equal(qs.length,3);assert.equal(qs[0].options[0].description,'Blue shade');
 assert.equal(qs[0].options.at(-1).label,'Others');assert.equal(qs[0].maximumTextLength,500);assert.equal(qs[1].multiple,true);
 assert.equal(qs[2].optional,true);assert.equal(qs[2].maximumTextLength,1000);
 f.plan.toolCallInfo.params._fromRequestUserInput=true;assert.equal(project(f).requests[0].questions.length,2);
 delete f.plan.toolCallInfo.params._fromRequestUserInput;f.context.omitDetail=true;assert.equal(project(f).requests[0].questions.length,2);
});
test('malformed or duplicate options decline the entire form',()=>{
 const f=fixture();f.plan.toolCallInfo.name='AskUserQuestion';f.context.questionID=f.plan.id;f.context.permissionID=null;
 for(const options of [null,[{label:'A'},{label:'A'}]]) {
  f.plan.toolCallInfo.params={questions:[{question:'Which?',options}]};assert.equal(project(f).requests[0].kind,'unsupported');
 }
});
test('mismatched ownership and oversized data fail rather than resolving an existing wait',()=>{
 const f=fixture();f.plan.messageId=id(8);assert.throws(()=>project(f));f.plan.messageId=f.message.messageId;
 f.plan.thought='x'.repeat(32769);assert.throws(()=>project(f));
});

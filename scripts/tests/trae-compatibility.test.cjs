const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const crypto = require('node:crypto');
const {Readable} = require('node:stream');
const path = require('node:path');
const sourceRoot = path.resolve(__dirname, '../../Notchline/Notchline/Products/Trae/Companion');
const compatibility = require(path.join(sourceRoot, 'trae-compatibility.js'));
const source = fs.readFileSync(path.join(sourceRoot, 'trae-extension.js'), 'utf8');

test('only explicitly verified builds have bindings and fingerprint requirements', () => {
  assert.deepEqual(Object.keys(compatibility.builds), ['3.5.91', '3.5.104']);
  for (const value of [undefined, null, '', '3.5.92', '3.5.105', '3.5.104-beta', '__proto__']) {
    assert.equal(compatibility.build(value), null);
    assert.throws(() => compatibility.resolve(() => { throw Error('Must not load'); }, value), /Unsupported Trae version/);
  }
  // The new selection API lives in a separate chunk; pin it as well as the entry point.
  assert.ok(compatibility.build('3.5.104').fingerprints['node_modules/@byted-icube/ai-modules-chat/dist/598.fe68f329.mjs']);
});

async function activation(version, contents) {
  const expected = crypto.createHash('sha256').update('verified bytes').digest('hex');
  let attached = false;
  const context = {exports:{}, require:name => {
    if (name === 'vscode') return {env:{appRoot:'/fixture'}, icube:{
      defineComponent:async () => { attached = true; throw Error('Attachment reached'); },
      addIcubeComponentInTitleCenter() {}
    }, Uri:{joinPath:()=>'bridge'}};
    if (name === './trae-compatibility.js') return {build:value => compatibility.build(value) ? {fingerprints:{'pinned.js':expected}} : null};
    if (name === 'node:fs') return {promises:{readFile:async()=>JSON.stringify({appVersion:version}),
      mkdir:async()=>{},lstat:async()=>({isDirectory:()=>true,isSymbolicLink:()=>false,uid:process.getuid(),mode:0o700})},
      createReadStream:()=> {if(contents===null)throw Error('Missing file');return Readable.from([contents]);},existsSync:()=>false};
    return require(name);
  }, process, Buffer, setTimeout, clearTimeout, setInterval, clearInterval};
  vm.runInNewContext(source, context);
  let error;
  try { await context.exports.activate({extensionUri:'/extension', subscriptions:[]}); } catch(e) {error=e.message;}
  return {attached,error};
}

test('activation verifies every supported build before attaching, and fails closed on unknown or damaged builds', async () => {
  for (const version of ['3.5.91','3.5.104']) {
    assert.deepEqual(await activation(version,'verified bytes'), {attached:true,error:'Attachment reached'});
    assert.equal((await activation(version,'modified bytes')).attached, false);
    assert.equal((await activation(version,null)).attached, false);
  }
  assert.equal((await activation('3.5.105','verified bytes')).attached, false);
});


test('new native rich permission fields cannot become an ordinary command approval', () => {
  const P = require(path.join(sourceRoot, 'trae-projection.js'));
  const id = n => String(n).repeat(24);
  const session = {sessionId:id(1),sessionType:'side_chat',name:'Test'};
  const message = {sessionId:id(1),messageId:id(2),turnId:id(3),replyToMessageId:id(4),status:'in_progress',agentId:'root',createdAt:1};
  for (const field of ['permission_request_rw_paths','permission_request_ro_paths','permission_request_networks','permission_request_reason','permission_request_command_prefixes','permission_request_mcp_tools']) {
    const plan = {id:id(5),messageId:id(2),agentId:'root',agentRunId:'root',
      confirmInfo:{confirm_status:'unconfirmed',auto_confirm:false,[field]:'additional permission'},
      toolCallInfo:{id:id(6),name:'RunCommand',params:{command:'printf test',requires_approval:true},result:{status:'running'}}};
    const row = P.project(session,message,[plan],{platform:'trae-ide',permissionID:id(5)});
    assert.equal(row.requests[0].kind,'unsupported');
    assert.equal(row.requests[0].command,null);
  }
});

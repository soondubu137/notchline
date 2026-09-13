// Passive projection of Trae 3.5.91's displayed V2 data. No native writes.
// Loaded before the component and also exercised directly by Node fixtures.
(function (root) {
  'use strict';
  const id = value => typeof value === 'string' && /^[a-f0-9]{24}$/.test(value);
  const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
  function text(value, limit = 32768) {
    if (typeof value !== 'string' || value.length > limit) throw Error('Unsupported text');
    return value;
  }
  function time(value) {
    if (value == null) return null;
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) throw Error('Unsupported timestamp');
    return value > 1e12 ? value / 1000 : value;
  }
  function questionSet(params, omitDetail, localize) {
    if (!object(params) || !Array.isArray(params.questions) || !params.questions.length || params.questions.length > 32) throw Error('Unsupported question set');
    const questions = params.questions.map((q, index) => {
      if (!object(q) || !Array.isArray(q.options) || !q.options.length || q.options.length > 64 ||
          (q.multiSelect != null && typeof q.multiSelect !== 'boolean')) throw Error('Unsupported question');
      const options = q.options.map(o => ({id: text(o.label), label: text(o.label), description: o.description == null ? null : text(o.description)}));
      if (new Set(options.map(o => o.id)).size !== options.length) throw Error('Ambiguous options');
      const custom = !options.some(o => o.id === '__other__');
      if (custom) options.push({id: '__other__', label: localize('trae-chat-core.ask-user-question.others', {}, 'Others'), description: null});
      return {id: `q-${index}`, header: q.header == null ? null : text(q.header), text: text(q.question), options,
        multiple: q.multiSelect === true, freeText: custom, optional: false, maximumTextLength: custom ? 500 : null};
    });
    if (!omitDetail && !params._fromRequestUserInput) questions.push({id: 'q-short-answer', header: null,
      text: localize('trae-chat-core.ask-user-question.additionalInfo', {}, "Is there any additional information you'd like to provide?"),
      options: [], multiple: false, freeText: true, optional: true, maximumTextLength: 1000});
    return questions;
  }
  function inScope(session, message, context) {
    return id(session.sessionId) && !session.parentSessionId && session.sessionType === 'side_chat' &&
      context.platform === 'trae-ide' && session.env !== 'remote' && (session.mode == null || session.mode === 'code') &&
      !session.remoteProjectId && !session.isRalphLoop && !context.planMode &&
      !message?.userMessageContext?.is_in_plan_mode && !message?.userMessageContext?.is_in_spec_mode;
  }
  function project(session, message, plans, context) {
    if (!inScope(session, message, context)) return null;
    if (!message || !id(message.messageId) || !id(message.turnId)) return null; // temporary assistant
    if (message.sessionId !== session.sessionId || !id(message.replyToMessageId)) throw Error('Mismatched message');
    if (!['in_progress', 'completed', 'canceled', 'failed'].includes(message.status)) return null;
    if (!Array.isArray(plans) || plans.length > 512) throw Error('Unsupported plan collection');
    let preview = null;
    const requests = [];
    const terminal = message.status !== 'in_progress';
    for (const p of plans) {
      if (!object(p) || !id(p.id) || p.messageId !== message.messageId || !object(p.toolCallInfo)) throw Error('Mismatched plan');
      // A child's words/requests never become the root's. Never export reasoning.
      if (p.hide || (p.parentAgentRunIds?.length ?? 0) > 0 || p.agentId !== message.agentId) continue;
      if (p.thought) preview = text(p.thought).slice(-4096);
      if (terminal || (p.id !== context.permissionID && p.id !== context.questionID)) continue;
      const tool = p.toolCallInfo, c = p.confirmInfo;
      if (!c || c.confirm_status !== 'unconfirmed' || c.auto_confirm === true ||
          ['success', 'skipped', 'failed', 'canceled'].includes(tool.result?.status) ||
          (c.auto_review_result && c.auto_review_result.fallback_to_manual_confirmation !== true)) continue;
      if (!id(tool.id)) throw Error('Missing tool identity');
      const request = {id:p.id, toolID:tool.id, producer:p.agentRunId ?? '', name:text(tool.name), kind:'unsupported', command:null, questions:null};
      if (tool.name === 'RunCommand' && p.id === context.permissionID) {
        const params = tool.params;
        // Rich permission fields need their own presentation; do not omit them.
        const rich = ['sandbox_status','sandbox_recovery_type','sandbox_config_command','block_level','block_command_list','hit_red_list','hit_black_list']
          .some(k => c[k] != null && c[k] !== false);
        if (!rich && object(params) && params.requires_approval === true &&
            Object.keys(params).every(k => ['command','blocking','requires_approval','cwd','command_description','command_type'].includes(k))) {
          request.kind = 'command'; request.command = text(params.command);
          request.details = Object.fromEntries(Object.entries(params).filter(([k]) => k !== 'command'));
        }
      } else if (tool.name === 'AskUserQuestion' && p.id === context.questionID) {
        try { request.questions = questionSet(tool.params, context.omitDetail, context.localize); request.kind = 'questions'; }
        catch { /* An identified wait with an unknown form returns to Trae. */ }
      }
      requests.push(request);
    }
    if (new Set(requests.map(r => r.id)).size !== requests.length) throw Error('Duplicate requests');
    return {threadID:session.sessionId, turnID:message.turnId, messageID:message.messageId, userMessageID:message.replyToMessageId,
      title:text(session.name ?? '', 4096), folder:session.workspacePath || session.mainFolder || null,
      status:message.status, startedAt:time(message.chatStartTime ?? message.createdAt), endedAt:time(message.chatEndTime),
      historical:message.isHistory === true, preview, requests};
  }
  const api = {id, questionSet, inScope, project};
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.__notchlineTraeProjectionV1 = api;
})(globalThis);

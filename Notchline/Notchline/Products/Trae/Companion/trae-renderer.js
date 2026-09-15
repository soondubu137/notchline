// Version-pinned companion: observes stores, reuses the product-owned client.
// Never connects/disconnects Aha, invokes event handlers, submits or answers.
(() => {
  'use strict';
  const tag = 'notchline-trae-reader-v1';
  if (customElements.get(tag)) return;
  const P = globalThis.__notchlineTraeProjectionV1;
  class Reader extends HTMLElement {
    constructor() {
      super();
      this.generation = 0; this.sequence = 0; this.last = new Map(); this.validated = new Map();
      this.listener = e => this.handle(e.detail).catch(() => this.fail('Trae displayed data is unavailable or incompatible.'));
      this.addEventListener('icube', this.listener);
    }
    emit(value) { this.dispatchEvent(new CustomEvent('icube-component', {detail:value})); }
    stop() {
      this.generation++; this.unsubscribe?.(); this.unsubscribe = null;
      this.featureUnsubscribe?.(); this.featureUnsubscribe = null;
      clearTimeout(this.timer); clearTimeout(this.retry); clearInterval(this.lease);
      this.last.clear(); this.validated.clear(); this.signatures = new Map(); this.pending = []; this.running = false;
    }
    fail(error) { this.stop(); this.emit({type:'unavailable', error}); }
    async handle(q) {
      if (!q || typeof q !== 'object') return;
      if (q.op === 'stop') { this.stop(); this.emit({requestId:q.requestId, ok:true}); return; }
      if (q.op === 'lease') { this.expires = Date.now() + 35000; this.emit({requestId:q.requestId, ok:!!this.unsubscribe}); return; }
      if (q.op === 'read') {
        // A failed optional reading never tears down lifecycle observation.
        let reading = null;
        try { reading = await this.readCompletion(); } catch {}
        this.emit({requestId:q.requestId, ok:true, reading}); return;
      }
      if (q.op === 'navigate') {
        let opened = false;
        try {
          if (!P.id(q.threadID) || !this.validated.has(q.threadID)) throw Error('Unobserved Thread');
          const native = await this.api.chat.getSession({chat_session_id:q.threadID});
          if (native?.code !== 0 || native.data?.chat_session_id !== q.threadID || native.data.parent_session_id ||
              native.data.session_type !== 'side_chat' || native.data.remote_project_id) throw Error('Thread unavailable');
          await this.v2.switchToSession(q.threadID);
          opened = await this.raise() && this.v2.getCurrentSession()?.sessionId === q.threadID;
        } catch { /* A refused navigation does not stop observation. */ }
        this.emit({requestId:q.requestId, ok:opened}); return;
      }
      if (q.op !== 'start') return;
      this.stop(); const generation = this.generation;
      this.retained = new Set(q.retainedThreadIDs ?? []);
      if (typeof q.moduleURL !== 'string' || !q.moduleURL.endsWith('/node_modules/@byted-icube/ai-modules-chat/dist/index.mjs')) throw Error('Invalid module');
      const module = await import(q.moduleURL); if (generation !== this.generation) return;
      const r = module.__webpack_require__;
      const c = r(6493).m.getInstance(); this.api = c.resolve(r(21458).R).getClient(); this.v2 = r(10678).Ok;
      try { this.nativeHost = r(20469).mc.getInstance().resolve(r(35007).k.INativeHostService); }
      catch { this.nativeHost = null; } // Read evidence and the exact window raise fail closed.
      this.stores = r(57419); this.store = r(22976).z.getStoreInstance();
      this.permission = r(71788).rT;
      // Read the same pure pending-question selector the form consumes.
      this.questions = r(95259).D;
      this.flags = r(1606).Cw; this.platform = r(67679).Ov;
      const i18n = r(40739).XT.tryResolve(r(78303).F.I18n);
      if (!i18n || typeof i18n.localize !== 'function') throw Error('Missing localisation');
      this.localize = i18n.localize.bind(i18n);
      if (typeof this.api.chat.getSession !== 'function' || typeof this.store.subscribe !== 'function' ||
          typeof this.questions?.get !== 'function') throw Error('Unsupported store');
      this.expires = Date.now() + 35000; this.sequence = 0; this.last.clear();
      this.unsubscribe = this.store.subscribe((state, previous) => {
        if (state.domain.session !== previous.domain.session || state.domain.message !== previous.domain.message ||
            state.domain.agentPlanItem !== previous.domain.agentPlanItem) this.capture();
      });
      this.featureUnsubscribe = this.flags.subscribe(() => this.capture());
      this.lease = setInterval(() => { if (Date.now() > this.expires) this.stop(); }, 15000);
      this.capture(true);
    }
    // Chromium ignores window.focus() without a user gesture, which a socket request never has, so
    // Trae raised only its last focused window. Force (2) activates Trae and focuses this window; a
    // minimised one spends its first call restoring, so ask again until focus lands.
    async raise() {
      if (typeof this.nativeHost?.focusWindow !== 'function') return false;
      const deadline = Date.now() + 1500;
      while (Date.now() < deadline) {
        await this.nativeHost.focusWindow({mode:2});
        // Wall clock, not a count: a hidden window's timers are throttled.
        const retry = Date.now() + 300;
        while (Date.now() < retry) {
          await new Promise(resolve => setTimeout(resolve, 50));
          if (document.hasFocus()) return true;
        }
      }
      return false;
    }
    completionVisible(messageID) {
      if (!P.id(messageID)) return false;
      const roots = document.querySelectorAll(`.turn__agent-message[data-message-id="${messageID}"]`);
      if (roots.length !== 1) return false;
      const e = roots[0].querySelector('.assistant-action-bar');
      if (!e?.checkVisibility({checkOpacity:true,checkVisibilityCSS:true})) return false;
      const b = e.getBoundingClientRect();
      let left = Math.max(0,b.left), top = Math.max(0,b.top);
      let right = Math.min(innerWidth,b.right), bottom = Math.min(innerHeight,b.bottom);
      for (let p=e.parentElement; p; p=p.parentElement) {
        const style = getComputedStyle(p), rect = p.getBoundingClientRect();
        if (/auto|scroll|hidden|clip/.test(style.overflowX)) { left=Math.max(left,rect.left); right=Math.min(right,rect.right); }
        if (/auto|scroll|hidden|clip/.test(style.overflowY)) { top=Math.max(top,rect.top); bottom=Math.min(bottom,rect.bottom); }
      }
      if (right-left < 1 || bottom-top < 1) return false;
      const hit = document.elementFromPoint((left+right)/2,(top+bottom)/2);
      return !!hit && (hit === e || e.contains(hit));
    }
    async readCompletion() {
      const generation = this.generation, host = this.nativeHost;
      if (!this.unsubscribe || !host || !document.hasFocus() || document.visibilityState !== 'visible') return null;
      const windowID = host.windowId;
      if (!Number.isSafeInteger(windowID) || windowID <= 0) return null;
      const focused = async () => {
        const active = await host.getActiveWindowId();
        const counts = await host.getWindowCountByState({isFocused:true});
        return active === windowID && counts?.focused === 1 && document.hasFocus();
      };
      if (!await focused()) return null;
      const threadID = this.v2.getCurrentSession()?.sessionId;
      if (!P.id(threadID)) return null;
      const sessions = this.stores.eA.allSessions.get();
      if (!Array.isArray(sessions) || sessions.length > 2048) return null;
      const session = sessions.find(s => s.sessionId === threadID);
      const message = this.stores.eA.lastAgentMessage.get(threadID);
      if (!session || !message || message.sessionId !== threadID || !P.id(message.turnId) || !P.id(message.messageId) ||
          !P.inScope(session,message,{platform:this.platform(),planMode:this.stores.eA.planMode.get(threadID)}) ||
          !['completed','canceled','failed'].includes(message.status) ||
          this.permission.get(threadID) || this.questions.get(threadID) || !this.completionVisible(message.messageId)) return null;
      const {turnId:turnID,messageId:messageID,status} = message;
      // Reading in another window does not transfer lifecycle ownership. Verify
      // its native root independently, even if this peer never observed a start.
      const native = await this.api.chat.getSession({chat_session_id:threadID});
      if (native?.code !== 0 || native.data?.chat_session_id !== threadID || native.data.parent_session_id ||
          native.data.session_type !== 'side_chat' || native.data.remote_project_id) return null;
      if (!await focused() || generation !== this.generation || !this.unsubscribe ||
          document.visibilityState !== 'visible' || this.v2.getCurrentSession()?.sessionId !== threadID) return null;
      const current = this.stores.eA.lastAgentMessage.get(threadID);
      const latestSessions = this.stores.eA.allSessions.get();
      const latestSession = Array.isArray(latestSessions) && latestSessions.length <= 2048
        ? latestSessions.find(s => s.sessionId === threadID) : null;
      if (current?.sessionId !== threadID || current?.turnId !== turnID || current?.messageId !== messageID || current?.status !== status ||
          !latestSession || !P.inScope(latestSession,current,{platform:this.platform(),planMode:this.stores.eA.planMode.get(threadID)}) ||
          this.permission.get(threadID) || this.questions.get(threadID) || !this.completionVisible(messageID)) return null;
      return {windowID, threadID, turnID, messageID, observedAt:Date.now()/1000};
    }
    capture(baseline = false) {
      try {
        const sessions = this.stores.eA.allSessions.get();
        if (!Array.isArray(sessions) || sessions.length > 2048) throw Error('Too many Threads');
        const rows = [], excluded = [];
        for (const s of sessions) {
          const m = this.stores.eA.lastAgentMessage.get(s.sessionId);
          if (m?.status !== 'in_progress' && !this.last.has(s.sessionId) && !this.retained.has(s.sessionId)) continue;
          const plans = m ? this.stores.TO.agentPlanItemsByMessageId.get(m.messageId) : [];
          const userMessage = m ? this.stores.eA.lastUserMessage.get(s.sessionId) : null;
          const context = {platform:this.platform(), planMode:this.stores.eA.planMode.get(s.sessionId),
            permissionID:this.permission.get(s.sessionId)?.id, questionID:this.questions.get(s.sessionId)?.id,
            omitDetail:!!this.flags.getState().disableAskUserQuestionOtherDetail, localize:this.localize};
          if (!P.inScope(s,m,context)) {
            if (this.last.has(s.sessionId) && this.last.get(s.sessionId) !== 'excluded') {
              this.last.set(s.sessionId, 'excluded'); excluded.push(s.sessionId);
            }
            continue;
          }
          const row = P.project(s, m, plans, context, userMessage);
          if (!row) continue;
          const encoded = JSON.stringify(row);
          if (this.last.get(row.threadID) === encoded) continue;
          this.last.set(row.threadID, encoded);
          rows.push(row);
        }
        if (this.last.size > 512) throw Error('Too many observed Threads');
        if (rows.length > 128) throw Error('Too many changing Threads');
        // Capture every lifecycle/request edge synchronously. A short content-only
        // coalescer below never overwrites a pending wait or Turn boundary.
        if (baseline || rows.length || excluded.length) this.enqueue({baseline, rows, excluded, at:Date.now()/1000});
      } catch { this.fail('Trae displayed data is unavailable or incompatible.'); }
    }
    enqueue(batch) {
      const signatures = batch.rows.map(row => [row.threadID, JSON.stringify([row.turnID,row.messageID,row.status,row.requests])]);
      const boundary = batch.baseline || batch.excluded.length > 0 || signatures.some(([id, value]) => this.signatures.get(id) !== value);
      for (const [id,value] of signatures) this.signatures.set(id,value);
      const tail = this.pending.at(-1);
      if (!boundary && tail && !tail.baseline && !tail.excluded.length && tail.rows.length === batch.rows.length &&
          tail.rows.every((row,index) => row.threadID === batch.rows[index].threadID && row.turnID === batch.rows[index].turnID &&
            row.status === batch.rows[index].status && JSON.stringify(row.requests) === JSON.stringify(batch.rows[index].requests))) {
        this.pending[this.pending.length - 1] = batch;
      } else {
        if (this.pending.length >= 128) { this.fail('Trae observation exceeded its queue limit.'); return; }
        this.pending.push(batch);
      }
      if (this.running) return;
      if (boundary) { clearTimeout(this.timer); this.timer = null; void this.flush(); }
      else if (!this.timer) this.timer = setTimeout(() => { this.timer = null; void this.flush(); }, 100);
    }
    async flush() {
      this.running = true; const generation = this.generation;
      try {
        while (this.pending.length && generation === this.generation) {
          const batch = this.pending.shift(), rows = [];
          for (const row of batch.rows) {
            if (generation !== this.generation) return;
            if (!this.validated.has(row.threadID)) {
              const n = await this.api.chat.getSession({chat_session_id:row.threadID});
              if (generation !== this.generation) return;
              if (n?.code !== 0 || n.data?.chat_session_id !== row.threadID || n.data.parent_session_id || n.data.session_type !== 'side_chat' || n.data.remote_project_id) throw Error('Root identity unavailable');
              let folder = row.folder;
              if (!folder && n.data.local_project_id) {
                const project = await this.api.project.getProject({project_id:n.data.local_project_id});
                if (generation !== this.generation) return;
                if (project?.code !== 0 || !project.data) throw Error('Project unavailable');
                const extra = typeof project.data.extra_info === 'string' ? JSON.parse(project.data.extra_info) : project.data.extra_info;
                folder = extra?.folder ?? null;
              }
              if (folder != null && (typeof folder !== 'string' || !folder.startsWith('/'))) throw Error('Invalid Project folder');
              this.validated.set(row.threadID, {folder});
            }
            rows.push({...row, folder:row.folder ?? this.validated.get(row.threadID).folder});
          }
          this.emit({type:'snapshot', schema:1, version:'3.5.91', sequence:++this.sequence, baseline:batch.baseline, observedAt:batch.at, rows, excluded:batch.excluded});
        }
      } catch { if (generation === this.generation) this.fail('Trae Thread identity could not be confirmed.'); }
      finally { if (generation === this.generation) this.running = false; }
    }
    disconnectedCallback() { this.stop(); }
  }
  customElements.define(tag, Reader);
})();

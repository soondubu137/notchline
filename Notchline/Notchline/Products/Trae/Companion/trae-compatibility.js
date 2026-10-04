// Exact builds only: private module identities are not stable across Trae updates.
(function (root) {
  'use strict';
  const builds = {
    '3.5.91': {
      fingerprints: {
        'out/main.js':'90fda6a0e5b4851a8a060afe1ebef3dbe69403934ab8f5669c98539b95acdf8d',
        'modules/ai-agent/libai_agent.dylib':'2e93b706d711574a717a985bc84c329aa903d9a75b4bcde83e01ce84d2450f6f',
        'out/vs/workbench/workbench.desktop.main.js':'a7a826e8191a386eb7c73bc3f6926924ef981f377721486c4480f0917b24276d',
        'node_modules/@byted-icube/ai-modules-chat/dist/index.mjs':'1198074030bb24e4b79f349c06ffc67b20feda642a9e35836c7194ed4c0fe7ac'
      },
      modules: {container:[6493,'m'], client:[21458,'R'], selection:[10678,'Ok'],
        hostContainer:[20469,'mc'], hostServices:[35007,'k'], stores:57419, store:[22976,'z'],
        permission:[71788,'rT'], questions:[95259,'D'], flags:[1606,'Cw'], platform:[67679,'Ov'],
        ports:[40739,'XT'], portIDs:[78303,'F']}
    },
    '3.5.104': {
      fingerprints: {
        "out/main.js": "a3b3f9e050f8a5d6720760900e4ca047d5605aa72c8ac3d9905b7649806dc831",
        "modules/ai-agent/libai_agent.dylib": "87677916de9f183ec5ad9b355dde12a0f4effb8202fe55e76246ba6ae5d55e02",
        "out/vs/workbench/workbench.desktop.main.js": "97aa42b23b9b5040695fb8a131b03761242ea6c12bc1ed779deec084d8425382",
        "node_modules/@byted-icube/ai-modules-chat/dist/index.mjs": "7c379d4d6e8b327b8a695bd604951de8449c78344729d417e95d6c1cf95da60f",
        "node_modules/@byted-icube/ai-modules-chat/dist/598.fe68f329.mjs": "15d1328552d251ec6d44dbd9ce3e0317b77a9713431a4dc176efbe4b568e0e61"
      },
      modules: {container:[32143,'mc'], client:[13055,'u'], selection:[27704,'apis'],
        hostContainer:[32143,'mc'], hostServices:[7825,'k'], stores:72024, store:[41571,'z'],
        permission:[35243,'rT'], questions:[49546,'D'], flags:[8893,'Cw'], platform:[75300,'Ov'],
        ports:[8594,'XT'], portIDs:[97594,'F']}
    }
  };
  const build = version => Object.hasOwn(builds, version) ? builds[version] : null;
  function resolve(require, version) {
    const verified = build(version);
    if (!verified) throw Error('Unsupported Trae version');
    const m = verified.modules, value = key => require(m[key][0])[m[key][1]];
    const api = value('container').getInstance().resolve(value('client')).getClient();
    let nativeHost = null;
    try { nativeHost = value('hostContainer').getInstance().resolve(value('hostServices').INativeHostService); }
    catch { /* Optional read evidence and exact window raising fail closed. */ }
    return {api, nativeHost, v2:value('selection'), stores:require(m.stores),
      store:value('store').getStoreInstance(), permission:value('permission'), questions:value('questions'),
      flags:value('flags'), platform:value('platform'), i18n:value('ports').tryResolve(value('portIDs').I18n)};
  }
  const api = {builds, build, resolve};
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.__notchlineTraeCompatibility = api;
})(globalThis);

// STATUS: PREPARED, NOT APPLIED. Figma Starter-plan MCP limit blocked execution.
// Target file: https://www.figma.com/design/sYIV8mmh67jYeN9ufAueAK
// Run inside use_figma with figma-use and figma-generate-design skills loaded.
// Syntax checked only; runtime and visual validation remain pending.
// Mascot insertion remains pending; the current script updates native UI and navigation.

const page=figma.currentPage;
const targetIds=['4:105','4:48','4:228','4:358'];
const targets=await Promise.all(targetIds.map(id=>figma.getNodeByIdAsync(id)));
const allFonts=new Map();for(const t of page.findAllWithCriteria({types:['TEXT']})){for(const s of t.getStyledTextSegments(['fontName']))allFonts.set(JSON.stringify(s.fontName),s.fontName);}
await Promise.all([...allFonts.values()].map(f=>figma.loadFontAsync(f)));
const variables=await figma.variables.getLocalVariablesAsync();const cv={};for(const v of variables)cv[v.name]=v;
const paint=(i)=>figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:1,g:1,b:1}},'color',cv['color/'+i]);
const primary=await figma.getNodeByIdAsync('4:15'); const labelKey=Object.keys(primary.componentPropertyDefinitions).find(k=>k.startsWith('Label#'));
const created=[],mutated=[],removed=[],links=[];
function track(n){created.push(n.id);return n;}
function text(parent,s,size=16,color=1,medium=false,w=380){const n=track(figma.createText());parent.appendChild(n);n.fontName={family:'Inter',style:medium?'Medium':'Regular'};n.fontSize=size;n.fills=[paint(color)];n.textAutoResize='HEIGHT';n.resize(w,24);n.characters=s;n.name=s.slice(0,50);return n;}
function stack(parent,name,x,y,w,gap=8){const n=track(figma.createAutoLayout('VERTICAL'));parent.appendChild(n);n.name=name;n.resize(w,80);n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.itemSpacing=gap;n.fills=[];n.x=x;n.y=y;return n;}
function rect(parent,name,x,y,w,h,color,r=0){const n=track(figma.createRectangle());parent.appendChild(n);n.name=name;n.resize(w,h);n.x=x;n.y=y;n.cornerRadius=r;n.fills=[paint(color)];return n;}
function dot(parent,x,y){const e=track(figma.createEllipse());parent.appendChild(e);e.resize(22,22);e.x=x;e.y=y;e.fills=[paint(2)];e.strokes=[paint(4)];e.strokeWeight=5;return e;}
function button(parent,label,w=380,secondary=false){const n=track(primary.createInstance());parent.appendChild(n);n.resize(w,54);n.setProperties({[labelKey]:label});if(secondary){n.fills=[paint(4)];for(const t of n.findAllWithCriteria({types:['TEXT']})){t.fills=[paint(2)];}}return n;}
function action(n,to){links.push({n,to});}
function chrome(f){rect(f,'iPhone 12 Pro Max notch',116,0,196,32,1,16);let n=text(f,'9:41',14,1,true,70);n.x=29;n.y=28;n=text(f,'LTE  ▰',13,1,false,75);n.x=328;n.y=28;rect(f,'Home indicator',154,902,120,5,1,3);}
function base(f,name){for(const c of [...f.children]){removed.push(c.id);c.remove();}mutated.push(f.id);f.name=name;f.fills=[paint(0)];f.resize(428,926);f.cornerRadius=42;f.clipsContent=true;chrome(f);}
function top(f,subtitle){const g=stack(f,'Map header',24,84,260,5);text(g,'Your world',26,1,true,260);text(g,subtitle,13,3,false,260);const b=button(f,'Offline places',112,true);b.x=292;b.y=86;action(b,'4:77');}
function reveal(f,initial=false){if(initial){dot(f,203,447);return;}const svg='<svg width="428" height="926" viewBox="0 0 428 926" xmlns="http://www.w3.org/2000/svg"><path d="M112 570 Q140 521 171 485 T253 375 Q279 347 307 300" fill="none" stroke="#FFFFFF" stroke-width="62" stroke-linecap="round"/><path d="M112 570 Q140 521 171 485 T253 375 Q279 347 307 300" fill="none" stroke="#D7D9CC" stroke-width="12" stroke-linecap="round"/><path d="M112 570 Q140 521 171 485 T253 375 Q279 347 307 300" fill="none" stroke="#46785B" stroke-width="3" stroke-dasharray="5 7" stroke-linecap="round"/></svg>';const v=track(figma.createNodeFromSvg(svg));f.appendChild(v);v.name='Only the traveled corridor is revealed';v.x=0;v.y=0;created.push(...v.findAll(()=>true).map(n=>n.id));dot(f,296,289);}
function footer(f,name='Walking controls'){const g=stack(f,name,24,676,380,10);g.paddingTop=16;g.paddingBottom=16;g.paddingLeft=16;g.paddingRight=16;g.cornerRadius=24;g.fills=[paint(4)];return g;}
function note(f,s){const n=text(page,s,13,3,false,428);n.x=f.x;n.y=f.y+944;}
const blank=targets[0],permission=targets[1],walking=targets[2],world=targets[3];
base(blank,'04 · Open directly to your blank world');top(blank,'Your first little adventure');
const greeting=stack(blank,'First walk invitation',44,356,340,10);greeting.counterAxisAlignItems='CENTER';let t=text(greeting,'A little world to uncover.',21,1,true,340);t.textAlignHorizontal='CENTER';t=text(greeting,'Start walking. Leave your first trail.',15,3,false,340);t.textAlignHorizontal='CENTER';
const homeActions=stack(blank,'Start or ask for inspiration',24,766,380,12);const start=button(homeActions,'Start walking');action(start,permission.id);const help=button(homeActions,'Help me choose somewhere',380,true);action(help,'4:77');
let maxX=Math.max(...page.children.map(n=>n.x+n.width));
function newScreen(name,index){let f=page.children.find(n=>n.type==='FRAME'&&n.name===name);if(!f){f=track(figma.createFrame());f.x=maxX+120;f.y=200+index*1080;}base(f,name);return f;}
const zero=newScreen('15 · Recording starts',0);
const paused=newScreen('16 · Paused outing',1);
base(permission,'02 · Location only when starting');top(permission,'Your first little adventure');
const intro=stack(permission,'Contextual location request',24,532,380,16);intro.fills=[paint(4)];intro.cornerRadius=26;intro.paddingTop=24;intro.paddingBottom=24;intro.paddingLeft=20;intro.paddingRight=20;
text(intro,'Let your steps draw the map',23,1,true,340);
text(intro,'Use your location to reveal the places you actually walk. Your trail stays on this iPhone.',16,3,false,340);
text(intro,'Recording continues with the screen locked, until you pause or finish.',14,3,false,340);
const allow=button(intro,'Continue to location',340);action(allow,zero.id);const later=button(intro,'Not now',340,true);action(later,blank.id);
note(permission,'Prototype simulates accepting the iOS location prompt. No GPS is accessed.');
function recording(f,mode){top(f,mode==='paused'?'Paused · your trail is kept':'Recording · saved on this iPhone');reveal(f,mode==='zero');const g=footer(f);text(g,mode==='zero'?'0:00 outside   ·   0 m walked':'18 min outside   ·   1.2 km walked',18,1,true,348);text(g,mode==='paused'?'Take your time. Resume when ready.':mode==='zero'?'Your map grows as you move.':'A little more of your world, uncovered.',14,3,false,348);const row=track(figma.createAutoLayout('HORIZONTAL'));g.appendChild(row);row.resize(348,54);row.itemSpacing=10;row.fills=[];const pause=button(row,mode==='paused'?'Resume':'Pause',169,true);action(pause,mode==='paused'?walking.id:paused.id);const finish=button(row,'Finish outing',169,true);action(finish,'4:319');const photo=button(g,'Keep a photo memory',348);action(photo,'4:264');}
recording(zero,'zero');base(walking,'08 · Walking reveals your world');recording(walking,'walking');recording(paused,'paused');
action(zero,walking.id);
base(world,'12 · Return to your growing world');top(world,'One outing. A little less fog.');reveal(world);
const memory=stack(world,'Saved memory on your map',176,462,172,6);memory.paddingLeft=12;memory.paddingTop=12;memory.paddingBottom=12;memory.cornerRadius=18;memory.fills=[paint(4)];text(memory,'Morning coffee',15,1,true,148);text(memory,'Your saved memory',12,3,false,148);action(memory,'4:398');
const worldActions=stack(world,'Continue exploring',24,766,380,12);const again=button(worldActions,'Start walking');action(again,walking.id);const ask=button(worldActions,'Help me choose somewhere',380,true);action(ask,'4:138');
const mutations=await Promise.all(['4:45','4:100','4:103','4:223','5:79'].map(id=>figma.getNodeByIdAsync(id)));const destinations=[blank.id,'4:138',blank.id,zero.id,zero.id];for(let i=0;i<mutations.length;i++){if(mutations[i]){action(mutations[i],destinations[i]);mutated.push(mutations[i].id);}}
const welcome=await figma.getNodeByIdAsync('4:21');welcome.name='01 · Optional introduction';mutated.push(welcome.id);
const download=await figma.getNodeByIdAsync('4:77');const skip=button(download,'Walk without a pack',380,true);skip.x=24;skip.y=866;skip.resize(380,36);action(skip,blank.id);
const updates={'4:47':'Optional introduction. Main prototype opens on the blank world.','4:106':'04  First screen · blank map, then walk','4:135':'No streets before walking. Location is requested when Start walking is tapped.','4:49':'02  Contextual location request','4:74':'No download needed to begin recording a walk.','4:102':'Optional branch: download places, then ask for suggestions.','4:229':'08  Full canvas · only traveled ground revealed','4:261':'Illustrative walk. Start screen advances when its canvas is tapped.','4:359':'12  Returning home · your progress remains','4:395':'Start another walk, ask for ideas, or tap your memory.','4:456':'Open your world · Walk to reveal · Ask for ideas when you want · Keep your memories'};
for(const [id,s]of Object.entries(updates)){const n=await figma.getNodeByIdAsync(id);if(n&&n.type==='TEXT'){n.characters=s;n.name=s.slice(0,65);n.textAutoResize='HEIGHT';n.resize(id==='4:456'?1700:428,n.height);mutated.push(n.id);}}
const recap=await figma.getNodeByIdAsync('4:319');for(const n of recap.findAllWithCriteria({types:['TEXT']})){if(n.characters==='A quiet park walk'){n.characters='Your little outing';mutated.push(n.id);}}
for(const a of links){await a.n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:a.to,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.2}}]}]);if(!created.includes(a.n.id))mutated.push(a.n.id);}
page.flowStartingPoints=[{nodeId:blank.id,name:'Open Life Off Desk · first walk'},{nodeId:world.id,name:'Returning to your world'},{nodeId:'4:138',name:'Optional · choose somewhere'}];
note(zero,'Tap the canvas to simulate walking progress. Pause, finish and photo actions are interactive.');
note(paused,'Pause keeps the revealed trail; Resume returns to the active outing.');
const changed=[blank,permission,zero,walking,paused,world];const audits=changed.map(f=>({id:f.id,name:f.name,descendants:f.findAll(()=>true).length,texts:f.findAllWithCriteria({types:['TEXT']}).length,instances:f.findAllWithCriteria({types:['INSTANCE']}).length,fonts:[...new Set(f.findAllWithCriteria({types:['TEXT']}).map(t=>t.fontName.family))]}));
await blank.screenshot({scale:1});await walking.screenshot({scale:1});
return {createdNodeIds:created,mutatedNodeIds:[...new Set(mutated)],removedNodeIds:removed,frames:audits,prototypeLinks:links.length,flows:page.flowStartingPoints,zeroId:zero.id,pausedId:paused.id};


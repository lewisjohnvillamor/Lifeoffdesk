'use strict';
const path = document.querySelector('#walk-path');
const reveal = document.querySelector('#reveal-path');
const walker = document.querySelector('#walker');
const toggle = document.querySelector('#walk-toggle');
const reset = document.querySelector('#walk-reset');
const title = document.querySelector('#walk-state-title');
const description = document.querySelector('#walk-description');
const announcement = document.querySelector('#walk-announcement');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let progress = 0, running = false, frame = 0, previous = 0, stage = -1;
const length = path.getTotalLength();
function paint() {
  path.style.strokeDashoffset = 100 - progress;
  reveal.style.strokeDashoffset = 100 - progress;
  const point = path.getPointAtLength(length * progress / 100);
  walker.setAttribute('transform', `translate(${point.x} ${point.y})`);
  document.querySelector('#stop-corner').classList.toggle('reached', progress >= 40);
  document.querySelector('#stop-park').classList.toggle('reached', progress >= 100);
  const nextStage = progress >= 100 ? 3 : progress >= 40 ? 2 : progress > 0 ? 1 : 0;
  if (stage !== nextStage) {
    stage = nextStage;
    const states = [
      ['Every adventure starts somewhere.', 'A little of the map is yours. Start walking to see what’s around the corner.'],
      ['A few steps, a fresh perspective.', 'As the simulated walk moves forward, a little more of the neighborhood appears.'],
      ['Hello, new corner.', 'A small detour opens up another part of your map. There’s a little green space ahead.'],
      ['A little adventure, just like that.', 'You’ve reached the end of this illustrated walk. In the app, your map grows through actual movement.']
    ];
    title.textContent = states[stage][0]; description.textContent = states[stage][1];
    if (progress) announcement.textContent = states[stage][0];
  }
}
function stop() { running = false; cancelAnimationFrame(frame); previous = 0; }
function tick(now) {
  if (!running) return;
  if (previous) progress = Math.min(100, progress + Math.min(now - previous, 100) / 140);
  previous = now; paint();
  if (progress >= 100) {stop();toggle.textContent = 'Walk again';return;}
  frame = requestAnimationFrame(tick);
}
function clearWalk() {stop();progress=0;stage=-1;paint();toggle.textContent='Start the demo walk';announcement.textContent='Demo walk reset.';}
toggle.addEventListener('click', () => {
  if (progress >= 100) clearWalk();
  if (reducedMotion.matches) {
    progress = Math.min(100, progress + 50);paint();toggle.textContent=progress>=100?'Walk again':'Continue the demo walk';return;
  }
  if (running) {stop();toggle.textContent='Continue the demo walk';announcement.textContent='Demo walk paused.';}
  else {running=true;toggle.textContent='Pause the demo walk';frame=requestAnimationFrame(tick);}
});
reset.addEventListener('click', clearWalk);
function pauseForVisibility() {if (running) {stop();toggle.textContent='Continue the demo walk';}}
document.addEventListener('visibilitychange',()=>{if(document.hidden)pauseForVisibility();});
reducedMotion.addEventListener('change',pauseForVisibility);
if ('IntersectionObserver' in window) new IntersectionObserver(entries=>{if(!entries[0].isIntersecting)pauseForVisibility();},{threshold:0.05}).observe(document.querySelector('#demo-map'));
paint();
const examples = {
  park:['“May 30 minutes ako. Gusto ko ng quiet na park.”','30 minutes. A park. A quieter moment.','The app uses your preferences to search its local catalog. Quietness needs supporting information; it won’t simply guess.'],
  coffee:['“Coffee break muna. May café ba nearby?”','A coffee stop, close to home.','Life Off Desk matches your café preference to nearby places and shows the distance clearly.'],
  new:['“Somewhere new naman, kahit malapit lang.”','A familiar area. A different corner.','Life Off Desk uses your explored world to surface a nearby place or street you have not discovered yet.']
};
const promptText = document.querySelector('#sample-prompt-text');
const promptAccessible = document.querySelector('#sample-prompt');
const promptBox = document.querySelector('.chat-prompt');
let typingRun = 0;
function typePrompt(text) {
  const run = ++typingRun;
  promptAccessible.textContent = text;
  promptBox.setAttribute('aria-label', `Example outing request: ${text}`);
  if (reducedMotion.matches) { promptText.textContent = text; return; }
  promptText.textContent = '';
  let index = 0;
  function typeNext() {
    if (run !== typingRun) return;
    promptText.textContent = text.slice(0, ++index);
    if (index < text.length) window.setTimeout(typeNext, index < 2 ? 180 : 34);
  }
  typeNext();
}
document.querySelectorAll('[data-example]').forEach(button=>button.addEventListener('click',()=>{
  document.querySelectorAll('[data-example]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));
  const [prompt,heading,reply]=examples[button.dataset.example];
  typePrompt(prompt);
  document.querySelector('#sample-title').textContent=heading;
  document.querySelector('#sample-reply').textContent=reply;
}));
if ('IntersectionObserver' in window) {
  const plannerObserver = new IntersectionObserver(entries => {
    if (!entries[0].isIntersecting) return;
    typePrompt(examples.park[0]);
    plannerObserver.disconnect();
  }, { threshold: .45 });
  plannerObserver.observe(document.querySelector('.conversation'));
}
const prototypeScreens = {
  map: {
    src: 'assets/mockup-map.jpg',
    alt: 'Life Off Desk shown inside an iPhone, with explored streets and discoveries on the map.',
    kicker: 'EXPLORE',
    title: 'Watch your world grow.',
    description: 'Every street you explore turns from fog into a map that feels like yours.'
  },
  route: {
    src: 'assets/mockup-route.jpg',
    alt: 'Life Off Desk shown inside an iPhone, with a suggested route following mapped streets.',
    kicker: 'GO SOMEWHERE',
    title: 'Find a different corner.',
    description: 'Choose a nearby place and see a suggested path along streets already in the map.'
  },
  coach: {
    src: 'assets/mockup-coach.jpg',
    alt: 'Life Off Desk shown on an iPhone with a Taglish on-device AI suggestion above the map.',
    kicker: 'LOCAL AI',
    title: 'A nudge that stays on your phone.',
    description: 'Ask naturally in English or Taglish and get ideas grounded in your explored world.'
  },
  recap: {
    src: 'assets/mockup-recap.jpg',
    alt: 'Life Off Desk shown inside an iPhone with a completed adventure recap and mascot card.',
    kicker: 'REMEMBER',
    title: 'Keep the little adventure.',
    description: 'New streets, places and time come together in a memory you can return to.'
  },
  help: {
    src: 'assets/mockup-help.jpg',
    alt: 'Life Off Desk shown inside an iPhone with the offline help assistant and sourced first-aid steps.',
    kicker: 'GET HELP',
    title: 'Useful guidance, even offline.',
    description: 'Ask in Taglish for sourced first-aid or road-trouble guidance when you need it.'
  }
};
const prototypeImage = document.querySelector('#prototype-image');
const prototypeButtons = [...document.querySelectorAll('[data-prototype]')];
const prototypeKicker = document.querySelector('#prototype-kicker');
const prototypeTitle = document.querySelector('#prototype-title');
const prototypeDescription = document.querySelector('#prototype-description');
Object.values(prototypeScreens).forEach(screen => { const preload = new Image(); preload.src = screen.src; });
prototypeButtons.forEach(button => { button.tabIndex = button.getAttribute('aria-selected') === 'true' ? 0 : -1; });
let prototypeChange = 0;
function selectPrototype(button) {
  const screen = prototypeScreens[button.dataset.prototype];
  if (!screen) return;
  const change = ++prototypeChange;
  prototypeButtons.forEach(item => {
    const selected = item === button;
    item.setAttribute('aria-selected', String(selected));
    item.tabIndex = selected ? 0 : -1;
  });
  prototypeImage.classList.add('is-changing');
  const update = () => {
    if (change !== prototypeChange) return;
    prototypeImage.src = screen.src;
    prototypeImage.alt = screen.alt;
    prototypeKicker.textContent = screen.kicker;
    prototypeTitle.textContent = screen.title;
    prototypeDescription.textContent = screen.description;
    requestAnimationFrame(() => prototypeImage.classList.remove('is-changing'));
  };
  reducedMotion.matches ? update() : window.setTimeout(update, 120);
}
prototypeButtons.forEach((button, index) => {
  button.addEventListener('click', () => selectPrototype(button));
  button.addEventListener('keydown', event => {
    if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
    event.preventDefault();
    const direction = event.key === 'ArrowRight' ? 1 : -1;
    const next = prototypeButtons[(index + direction + prototypeButtons.length) % prototypeButtons.length];
    next.focus();
    selectPrototype(next);
  });
});
document.querySelector('#year').textContent=new Date().getFullYear();

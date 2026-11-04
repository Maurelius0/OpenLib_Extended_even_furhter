const {chromium}=require('playwright');
const fs=require('fs');
const path=require('path');
(async()=>{
 const root=path.resolve(__dirname,'..');
 const fixture=JSON.parse(fs.readFileSync(process.env.READER_LINK_FIXTURE,'utf8'));
 const dart=fs.readFileSync(path.join(root,'lib/ui/epub_viewer.dart'),'utf8');
 const css=dart.split('<style>')[1].split('</style>')[0].replace('${_fontSize}',20);
 const script=fs.readFileSync(path.join(root,'lib/ui/components/epub_pagination.js'),'utf8');
 const browser=await chromium.launch({executablePath:process.env.READER_CHROMIUM_PATH,headless:true,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:412,height:800},hasTouch:true});
 async function load(i){
  await page.setContent(`<style>${css}</style><div id="viewport"><main id="book" class="reader-section">${fixture.bodies[i]}</main></div>`);
  await page.evaluate(()=>{window.calls=[];window.flutter_inappwebview={callHandler:(...args)=>window.calls.push(args)}});
  await page.addScriptTag({content:script});
  await page.evaluate(async()=>{await Promise.all(Array.from(document.images).map(i=>i.decode().catch(()=>{})));window.readerRestore(0,false)});
  await page.waitForTimeout(30);
 }
 let checked=0;
 for(let i=0;i<fixture.spine.length && checked<6;i++){
  await load(i);
  const candidates=await page.evaluate(()=>Array.from(document.querySelectorAll('a[data-reader-target]')).map((e,index)=>({target:e.dataset.readerTarget,index})).filter(e=>!/^https?:/.test(e.target)&&e.target.includes('#')));
  for(const candidate of candidates.slice(0,6-checked)){
   await load(i);
   const point=await page.evaluate(index=>{
    const node=document.querySelectorAll('a[data-reader-target]')[index];
    node.id='test-click-link';window.readerAnchor(node.id);
    const bounds=document.getElementById('viewport').getBoundingClientRect();
    const rect=Array.from(node.getClientRects()).find(r=>r.left<bounds.right&&r.right>bounds.left&&r.top<bounds.bottom&&r.bottom>bounds.top);
    return rect?{x:Math.max(bounds.left+1,rect.left+1),y:Math.max(bounds.top+1,rect.top+2)}:null;
   },candidate.index);
   if(!point)throw Error('source link not visible');
   await page.touchscreen.tap(point.x,point.y);
   const links=await page.evaluate(()=>window.calls.filter(c=>c[0]==='link'));
   if(links.length!==1||links[0][1]!==candidate.target)throw Error('real book tap did not route '+candidate.target);
   const split=candidate.target.indexOf('#'), file=candidate.target.slice(0,split),anchor=candidate.target.slice(split+1);
   const target=fixture.spine.findIndex(f=>decodeURIComponent(f)===file);
   if(target<0)throw Error('target chapter missing');
   await load(target);
   if(!await page.evaluate(id=>window.readerAnchor(id),anchor))throw Error('destination anchor missing');
   const visible=await page.evaluate(id=>{
    const node=document.getElementById(id)||Array.from(document.querySelectorAll('[name]')).find(e=>e.getAttribute('name')===id);
    const bounds=document.getElementById('viewport').getBoundingClientRect();
    return Array.from(node.getClientRects()).some(r=>r.left>=bounds.left-1&&r.left<bounds.right&&r.top>=bounds.top-1&&r.top<bounds.bottom);
   },anchor);
   if(!visible)throw Error('destination not on displayed page: '+candidate.target);
   checked++;
  }
 }
 if(checked<6)throw Error('insufficient real book links');
 console.log('PASS '+checked+' real EPUB touch links and visible destination pages');
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});

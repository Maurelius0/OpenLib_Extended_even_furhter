const {chromium}=require('playwright');
const fs=require('fs');
const path=require('path');
const root=path.resolve(__dirname,'..');
if(!process.env.READER_TEST_HTML) throw Error('Set READER_TEST_HTML to a prepared test EPUB section');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.READER_CHROMIUM_PATH,headless:true,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:412,height:800}});
 const dart=fs.readFileSync(path.join(root,'lib/ui/epub_viewer.dart'),'utf8');
 const css=dart.split('<style>')[1].split('</style>')[0].replace('${_fontSize}',20);
 const body=fs.readFileSync(process.env.READER_TEST_HTML,'utf8');
 const script=fs.readFileSync(path.join(root,'lib/ui/components/epub_pagination.js'),'utf8');
 await page.setContent(`<html><head><style>${css}</style></head><body><div id="viewport"><main id="book" class="reader-section">${body}</main></div></body></html>`);
 await page.evaluate(()=>{window.calls=[];window.readerChapter=1;window.flutter_inappwebview={callHandler:(...v)=>window.calls.push(v)}});
 await page.addScriptTag({content:script});
 await page.evaluate(async()=>{await Promise.all(Array.from(document.images).map(i=>i.decode().catch(()=>{})));window.readerRestore(0,false)});
 await page.waitForTimeout(60);
 for(const size of [20,28]){
  await page.evaluate(s=>window.readerSettings(s,false),size);await page.waitForTimeout(60);
  const styles=await page.evaluate(()=>{
   const a=getComputedStyle(document.querySelector('#id_Toc70759518'));
   const b=getComputedStyle(document.querySelector('#id_Toc70759517'));
   const p=getComputedStyle(document.querySelector('p.block_8'));
   return {a:parseFloat(a.fontSize),b:parseFloat(b.fontSize),weight:a.fontWeight,paragraph:parseFloat(p.fontSize)};
  });
  if(styles.a<styles.paragraph*1.35||styles.b<styles.paragraph*1.35||Number(styles.weight)<600)throw Error('headings not styled '+JSON.stringify(styles));
  const measured=await page.evaluate(b=>window.readerMeasure(b),body);
  const live=await page.evaluate(()=>window.calls.filter(c=>c[0]==='reader').at(-1)[1]);
  if(measured.count!==live.count)throw Error('pagination mismatch '+JSON.stringify({measured,live}));
  console.log('PASS real headings and font scaling at '+size+'px; '+live.count+' pages in section');
 }
 await page.evaluate(()=>{window.calls=[];for(let p=0;p<30;p++)window.readerPreviewPage(p)});
 const preview=await page.evaluate(()=>window.calls);
 if(preview.length!==30||preview.some(c=>!c[1].preview||c[1].reading))throw Error('preview persisted as reading');
 await page.evaluate(()=>window.readerGoPage(20));
 const commit=await page.evaluate(()=>window.calls.at(-1)[1]);
 if(commit.page!==20||!commit.reading||commit.preview)throw Error('final commit mismatch');
 console.log('PASS preview page changes are temporary; release commits exact page');
 await page.evaluate(()=>window.readerAnchor('id_Toc70759518'));
 const anchor=await page.evaluate(()=>window.calls.at(-1)[1]);
 if(anchor.page<1)throw Error('anchor jump failed');
 console.log('PASS contents anchor after measurement with publisher styling');
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});

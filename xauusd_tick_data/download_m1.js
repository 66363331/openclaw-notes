const { getHistoricalRates } = require("dukascopy-node");

async function download() {
  const dir = "/home/lilei/.openclaw/workspace/xauusd_tick_data";
  const fs = require("fs");
  
  // M1 data for Feb 2026
  console.log("下载 2026年2月 M1数据...");
  try {
    const feb = await getHistoricalRates({
      instrument: "xauusd",
      dates: { from: new Date("2026-02-01"), to: new Date("2026-02-28") },
      timeframe: "m1",
    });
    const febCsv = "timestamp,askPrice,bidPrice\n" + feb.map(r => `${r.timestamp},${r.ask},${r.bid}`).join("\n");
    fs.writeFileSync(`${dir}/xauusd_2026-02_m1.csv`, febCsv);
    console.log(`  2月完成: ${feb.length} 条`);
  } catch(e) { console.log("  2月失败:", e.message); }

  await new Promise(r => setTimeout(r, 10000));

  // M1 data for March 2026
  console.log("下载 2026年3月 M1数据...");
  try {
    const mar = await getHistoricalRates({
      instrument: "xauusd",
      dates: { from: new Date("2026-03-01"), to: new Date("2026-03-31") },
      timeframe: "m1",
    });
    const marCsv = "timestamp,askPrice,bidPrice\n" + mar.map(r => `${r.timestamp},${r.ask},${r.bid}`).join("\n");
    fs.writeFileSync(`${dir}/xauusd_2026-03_m1.csv`, marCsv);
    console.log(`  3月完成: ${mar.length} 条`);
  } catch(e) { console.log("  3月失败:", e.message); }

  await new Promise(r => setTimeout(r, 10000));

  // M1 data for April 2026
  console.log("下载 2026年4月(1-3) M1数据...");
  try {
    const apr = await getHistoricalRates({
      instrument: "xauusd",
      dates: { from: new Date("2026-04-01"), to: new Date("2026-04-03") },
      timeframe: "m1",
    });
    const aprCsv = "timestamp,askPrice,bidPrice\n" + apr.map(r => `${r.timestamp},${r.ask},${r.bid}`).join("\n");
    fs.writeFileSync(`${dir}/xauusd_2026-04_m1.csv`, aprCsv);
    console.log(`  4月完成: ${apr.length} 条`);
  } catch(e) { console.log("  4月失败:", e.message); }

  console.log("完成！");
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.csv'));
  files.forEach(f => {
    const s = fs.statSync(`${dir}/${f}`);
    console.log(`  ${f}: ${(s.size/1024).toFixed(1)} KB`);
  });
}

download();

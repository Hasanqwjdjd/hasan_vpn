/// لیست کامل SNI / جعل نشانگر نام سرور.
/// ترکیب سایت‌های ایرانی، بین‌المللی و CDN که معمولاً whitelist هستند.
class TorSniPresets {
  TorSniPresets._();

  static const String defaultSni = 'certum.pl';

  static const List<String> all = <String>[
    // ═══ سایت‌های ایرانی پربازدید ═══
    'neshan.org', 'subkade.ir', 'gifpey.info', 'shaadbin.ir',
    'uupload.ir', 'gerdoo.me', 'bazion.ir', 'abadis.ir',
    'ikac.ir', 'ebooksworld.ir', 'iranicard.ir', 'gameq.ir',
    'melovaz.ir', 'daneshpaz.top', 'uploadina.com',
    'sarzamindownload.com', 'asiatech.ir', 'shecan.ir',
    'par30games.net', '3fa.ir', 'taaghche.com', 'downloadly.ir',
    'oldtowns.top', 'cafebazaar.ir', 'shaparak.ir', 'uploadkon.ir',
    'varzesh3.com', 'hooshang.ai', 'downloadha.com', 'filimo.com',
    'farsroid.com', 'bosgame.ir', 'divar.ir', 'snap.ir', 'nic.ir',
    'flzios.ir', 'digikala.com', 'fastdic.com',
    'hooshyar.golrang.ai', 'aparat.com', 'download.ir', 'yasdl.com',
    'pastehub.ir', 'iranmatlab.ir', 'bitpin.ir', 'my.files.ir',
    'post.ir', 'picofile.com', 'namnak.com', 'gov.ir', 'nixfile.com',
    'pirategames.ir', 'balad.ir', 'faraazin.ir', 'vgdl.ir',
    'aharvesal.ir', 'chat.smartbytes.ir', 'behmelody.in',
    'cup.theazizi.ir', 'alibaba.ir', 'zarebin.ir', 'patoghu.com',
    'subzone.ir', 'navaar.ir', 'zoomit.ir', 'linklick.ir',
    'dlfox.com', 'fidibo.com', 'tamin.ir', 'guardnet.ir',
    '2059.ir', 'irimo.ir', 'm.ulni.ir', 'myket.ir',
    'telewebion.com', 'airport.ir', 'radio.9craft.ir', 'torob.com',
    'rubika.ir', 'dic.b-amooz.com', 'mizanonline.ir',
    'search.bertina.ir', 'dls2.iran-gamecenter-host.com',
    'dl2.sermoviedown.pw',
    // ═══ بین‌المللی و CDN ═══
    'certum.pl', 'letsencrypt.org', 'sourceforge.net', 'google.com',
    'scholar.google.com', 'libra-books.com', 'uploadboy.com',
    'soft98.ir', 'epicgames.com', 'gitlab.com', 'mail.google.com',
    'support.google.com', 'search.google.com', 'vercel.com',
    'okta.com', 'cdnjs.com', 'openai.com', 'chatgpt.com',
    'python.org', 'cdn77.com', 'centos.org', 'atlassian.com',
    'site.google.com', 'sheets.google.com', 'react.dev',
    'ubuntu.com', 'email.google.com', 'vercel.app', 'chess.com',
    'gapgpt.app', 'ninisite.com',
    // ═══ Google APIs و dns ═══
    'play.googleapis.com', 'drive.google.com', 'cdn.ampproject.org',
    'api.github.com', 'ajax.aspnetcdn.com', 'verizon.com',
    'eset.com', 'supermario.corp.google.com', 'gold-team.org',
    'rio.ggusers.com', 'news.google.com', 'googlevideo.com',
    // ═══ SNI مخصوص ═══
    'nairobi.saymyname.website', 'berlin.saymyname.website',
    'actualities.google.com', 'myf2mi.top', 'f2me.top',
    'chat.boofai.com',
    // ═══ sslip (IP-based) ═══
    '8.6.112.0.sslip.io', '2.188.21.46.sslip.io',
    '2.188.21.130.sslip.io', '162.159.152.4.sslip.io',
    '87.107.110.155.sslip.io',
  ];
}

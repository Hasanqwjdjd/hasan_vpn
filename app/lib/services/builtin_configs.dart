/// کانفیگ‌های پیش‌فرض که با اپ بسته‌بندی می‌شوند.
/// این گروه در صفحه اشتراک‌ها همیشه هست و قابل حذف نیست.
class BuiltinConfigs {
  static const String groupId = 'builtin_hasan';
  static const String groupName = 'Hasan Built-in ⚡';

  /// کانفیگ‌های خام (همون فرمتی که کاربر کپی می‌کنه).
  static const List<String> rawConfigs = <String>[
    // Trojan - calmlunch
    r'trojan://humanity@172.67.217.240:443?path=%2Fassignment&security=tls&fm=%7B%22tcp%22%3A%20%5B%7B%22type%22%3A%20%22fragment%22%2C%20%22settings%22%3A%20%7B%22packets%22%3A%20%22tlshello%22%2C%20%22lengths%22%3A%20%5B%225%22%2C%20%2294%22%2C%20%221%22%5D%2C%20%22delays%22%3A%20%5B%220%22%5D%2C%20%22maxSplit%22%3A%20%220%22%7D%7D%2C%7B%22type%22%3A%20%22fragment%22%2C%20%22settings%22%3A%20%7B%22packets%22%3A%20%221-1%22%2C%20%22lengths%22%3A%20%5B%22109%22%2C%20%221%22%5D%2C%20%22delays%22%3A%20%5B%221%22%5D%2C%20%22maxSplit%22%3A%20%22355%22%7D%7D%5D%7D&insecure=0&host=www.calmlunch.com&fp=unsafe&type=ws&allowInsecure=0&sni=www.calmlunch.com#hamedvpns',

    // VLESS - throbbing-mountain worker
    r'vless://f22856f8-66f0-4655-ba86-5385971e1302@172.67.217.240:443?path=%2Fpyip%3DProxyIP.US.CMLiussss.net&security=tls&encryption=none&fm=%7B%22tcp%22%3A%20%5B%7B%22type%22%3A%20%22fragment%22%2C%20%22settings%22%3A%20%7B%22packets%22%3A%20%22tlshello%22%2C%20%22lengths%22%3A%20%5B%225%22%2C%20%2294%22%2C%20%221%22%5D%2C%20%22delays%22%3A%20%5B%220%22%5D%2C%20%22maxSplit%22%3A%20%220%22%7D%7D%2C%7B%22type%22%3A%20%22fragment%22%2C%20%22settings%22%3A%20%7B%22packets%22%3A%20%221-1%22%2C%20%22lengths%22%3A%20%5B%22109%22%2C%20%221%22%5D%2C%20%22delays%22%3A%20%5B%221%22%5D%2C%20%22maxSplit%22%3A%20%22355%22%7D%7D%5D%7D&insecure=0&host=throbbing-mountain-45e9.314-df3.workers.dev&fp=unsafe&type=ws&allowInsecure=0&sni=throbbing-mountain-45e9.314-df3.workers.dev#hamedvpns-US',

    // VLESS - calm-tree worker
    r'vless://080fad7c-ff4b-499f-ab5d-52d69ea5745a@172.67.217.240:443?path=%2Fpyip%3DTelegram%F0%9F%87%A8%F0%9F%87%B3%2B%40soskeynets&security=tls&encryption=none&fm=%7B%22tcp%22%3A%20%5B%7B%22type%22%3A%20%22fragment%22%2C%20%22settings%22%3A%20%7B%22packets%22%3A%20%22tlshello%22%2C%20%22lengths%22%3A%20%5B%225%22%2C%20%2294%22%2C%20%221%22%5D%2C%20%22delays%22%3A%20%5B%220%22%5D%2C%20%22maxSplit%22%3A%20%220%22%7D%7D%2C%7B%22type%22%3A%20%22fragment%22%2C%20%22settings%22%3A%20%7B%22packets%22%3A%20%221-1%22%2C%20%22lengths%22%3A%20%5B%22109%22%2C%20%221%22%5D%2C%20%22delays%22%3A%20%5B%221%22%5D%2C%20%22maxSplit%22%3A%20%22355%22%7D%7D%5D%7D&insecure=0&host=calm-tree-22b0.215-d2a.workers.dev&fp=unsafe&type=ws&allowInsecure=0&sni=calm-tree-22b0.215-d2a.workers.dev#hamedvpns-CA',

    // Hysteria2
    r'hysteria2://eBTe6Ax2pUts8oMEWoYVDfnSlHfkLffQ@nas.aizhzo.com:5010?security=tls&obfs=salamander&obfs-password=7M4RXPFcQyQEGbkxBPfXo4bilMhCW2U9&insecure=0&sni=nas.aizhzo.com#hamedvpns-IR',

    // VLESS - hasanzeus
    r'vless://36ba6d53-6867-4ad8-babd-d7d000000000@vy2i69-z707bh-2sjvq6.ekz8gsezum2s.workers.dev:443?path=%2Fsync&security=tls&encryption=none&insecure=0&host=vy2i69-z707bh-2sjvq6.ekz8gsezum2s.workers.dev&fp=chrome&type=ws&allowInsecure=0&sni=vy2i69-z707bh-2sjvq6.ekz8gsezum2s.workers.dev#V-Core-443',

    // ─── Hysteria2 — SferaVPN (Germany) ───
    r'hysteria2://cd74c0a406664a5bc0bac098220a2468@de1.sferavpn.pro:443?security=tls&obfs=salamander&obfs-password=44f1c1e2f8b99e792ceed574627a1eb0&insecure=1&sni=de1.sferavpn.pro#hamedvpns-DE',
    r'hysteria2://cd74c0a406664a5bc0bac098220a2468@de1.sferavpn.pro:443?security=tls&obfs=salamander&obfs-password=44f1c1e2f8b99e792ceed574627a1eb0&insecure=0&sni=de1.sferavpn.pro#hamedvpns-DE-secure',

    // ─── Hysteria2 — AspidNet (Germany) ───
    r'hysteria2://QCgqi_I4EkV8UR-OgQ_tG4EnVTEVvIyR2GgRBzrIn2s@hy2-new.aspidnet.xyz:443?security=tls&obfs=salamander&obfs-password=c1b4086fea89914496c7e10967a419216566&insecure=0&sni=hy2-new.aspidnet.xyz#hamedvpns-DE-aspid',

    // ─── Hysteria2 — SferaVPN (Russia) ───
    r'hysteria2://cd74c0a406664a5bc0bac098220a2468@ru1.sferavpn.pro:443?security=tls&obfs=salamander&obfs-password=44f1c1e2f8b99e792ceed574627a1eb0&insecure=0&sni=ru1.sferavpn.pro#hamedvpns-RU',
  ];

  /// کانفیگ‌های اضافی که از GitHub بارگیری می‌شوند (روزانه).
  /// این‌ها رو از repoهای عمومی می‌گیریم، نه از تلگرام.
  static const List<String> dailySources = <String>[
    'https://raw.githubusercontent.com/barry-far/V2ray-Config/main/All_Configs_Sub.txt',
    'https://raw.githubusercontent.com/mfuu/v2ray/master/v2ray',
  ];
}

import 'package:flutter/material.dart';
import '../models/server.dart';
import '../services/server_tester.dart';
import '../services/connector.dart';
import '../widgets/server_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<VpnServer> _servers = List.from(kServers);
  VpnServer? _selected;
  bool _testing = false;
  bool _autoMode = true;
  bool _connecting = false;
  String _status = 'آماده';
  int _tested = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runTest());
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _tested = 0;
      _status = 'در حال تست سرورها...';
    });

    await ServerTester.testAll(_servers, onProgress: (done, total) {
      setState(() => _tested = done);
    });

    final best = ServerTester.fastest(_servers);
    setState(() {
      _testing = false;
      _servers = List.from(_servers);
      if (best != null && _autoMode) {
        _selected = best;
        _status = 'سریع‌ترین: ${best.name}';
      } else {
        _status = 'آماده';
      }
    });
  }

  Future<void> _connect() async {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اول یه سرور انتخاب کن')),
      );
      return;
    }

    setState(() {
      _connecting = true;
      _status = 'در حال اتصال...';
    });

    final ok = await Connector.connect(_selected!);

    setState(() {
      _connecting = false;
      _status = ok
          ? 'v2rayNG باز شد — Connect رو بزن!'
          : 'v2rayNG نصب نیست! اول نصبش کن';
    });

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('v2rayNG رو نصب کن، بعد دوباره امتحان کن'),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090C),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'حسن',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _status,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _testing || _connecting ? null : _connect,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _selected != null
                        ? const Color(0xFF3DCF9A)
                        : Colors.white24,
                    width: 3,
                  ),
                  color: _selected != null
                      ? const Color(0xFF3DCF9A).withOpacity(0.1)
                      : Colors.transparent,
                ),
                child: Center(
                  child: _testing || _connecting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.power_settings_new,
                              color: _selected != null
                                  ? const Color(0xFF3DCF9A)
                                  : Colors.white38,
                              size: 40,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selected != null ? 'اتصال' : 'انتخاب سرور',
                              style: TextStyle(
                                color: _selected != null
                                    ? const Color(0xFF3DCF9A)
                                    : Colors.white38,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF12141A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Switch(
                            value: _autoMode,
                            onChanged: (v) => setState(() => _autoMode = v),
                            activeColor: const Color(0xFF3DCF9A),
                          ),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Text(
                              'اتصال خودکار',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _testing ? null : _runTest,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF12141A),
                      side: const BorderSide(color: Colors.white12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'سرورها',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_testing)
                          Text(
                            '$_tested / ${_servers.length}',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ..._servers.map((s) => ServerTile(
                        server: s,
                        selected: _selected?.id == s.id,
                        onTap: () => setState(() => _selected = s),
                      )),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

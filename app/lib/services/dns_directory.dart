// app/lib/services/dns_directory.dart
//
// Combines the regional dns_directory_*.dart files into one directory.
// Splitting by region keeps each file small enough to actually edit;
// this file is the only place that needs to know they all exist.
//
// NOTE ON COUNT: this ships with real, sourced entries (see the
// "source" field on each DnsEntry, and the header comment of each
// regional file) rather than 1000 invented ones. Current count is
// printed by kDnsDirectoryStats below — see chat for the honest
// breakdown. More regions can be added the same way later.

import '../models/dns_entry.dart';
import 'dns_directory_ir.dart';
import 'dns_directory_us.dart';
import 'dns_directory_eu.dart';
import 'dns_directory_apac.dart';
import 'dns_directory_other.dart';

/// All entries, IR first since this app's primary audience is Iran.
final List<DnsEntry> kAllDnsEntries = <DnsEntry>[
  ...kIrDnsDirectory,
  ...kUsDnsDirectory,
  ...kEuDnsDirectory,
  ...kApacDnsDirectory,
  ...kOtherDnsDirectory,
];

/// Lazy-ish accessor for the UI layer: avoids re-walking tag sets on
/// every rebuild by caching simple lookups. Called once at screen init.
class DnsDirectoryIndex {
  final List<DnsEntry> all;
  final Map<String, DnsEntry> byId;
  final Map<String, List<DnsEntry>> byCountry;

  DnsDirectoryIndex._(this.all, this.byId, this.byCountry);

  factory DnsDirectoryIndex.build() {
    final byId = <String, DnsEntry>{};
    final byCountry = <String, List<DnsEntry>>{};
    for (final e in kAllDnsEntries) {
      byId[e.id] = e;
      byCountry.putIfAbsent(e.country, () => []).add(e);
    }
    return DnsDirectoryIndex._(kAllDnsEntries, byId, byCountry);
  }

  List<DnsEntry> forCountry(String iso2) => byCountry[iso2] ?? const [];

  List<DnsEntry> search(String query) {
    if (query.trim().isEmpty) return all;
    final q = query.toLowerCase();
    return all
        .where((e) =>
            e.name.toLowerCase().contains(q) ||
            e.provider.toLowerCase().contains(q) ||
            e.country.toLowerCase().contains(q) ||
            (e.primary?.contains(q) ?? false) ||
            (e.primaryV6?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  List<DnsEntry> filterByTag(DnsTag tag) =>
      all.where((e) => e.tags.contains(tag)).toList();
}

int get kDnsDirectoryTotalCount => kAllDnsEntries.length;

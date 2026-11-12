import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/tables.dart';
import '../struct/databaseGlobal.dart';

class PersonSummary {
  PersonSummary({required this.name});
  final String name;
  double totalSent = 0;
  double totalReceived = 0;
  final List<Transaction> transactions = [];

  double get netBalance => totalReceived - totalSent;
}

class PeopleTransactionsPage extends StatefulWidget {
  const PeopleTransactionsPage({super.key});

  @override
  State<PeopleTransactionsPage> createState() => _PeopleTransactionsPageState();
}

class _PeopleTransactionsPageState extends State<PeopleTransactionsPage> {
  String? _selectedPerson;
  String _searchQuery = '';
  bool _sortNewestFirst = true;

  List<PersonSummary> _groupByPerson(List<Transaction> allTxns) {
    final map = <String, PersonSummary>{};

    for (final t in allTxns) {
      final personName = _extractPersonName(t);
      if (personName == null || personName.isEmpty) continue;

      final key = personName.toLowerCase();
      final summary = map.putIfAbsent(key, () => PersonSummary(name: personName));
      summary.transactions.add(t);

      if (t.income) {
        summary.totalReceived += t.amount.abs();
      } else {
        summary.totalSent += t.amount.abs();
      }
    }

    final list = map.values.toList()
      ..sort((a, b) => b.transactions.length.compareTo(a.transactions.length));

    for (final p in list) {
      p.transactions.sort((a, b) => _sortNewestFirst
          ? b.dateCreated.compareTo(a.dateCreated)
          : a.dateCreated.compareTo(b.dateCreated));
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      return list.where((p) => p.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  String? _extractPersonName(Transaction t) {
    // 1. Check explicit Person tag from SMS engine
    final tagMatch = RegExp(r'Person:([^•\[]+)').firstMatch(t.note);
    if (tagMatch != null) {
      return tagMatch.group(1)!.trim();
    }
    // 2. Include manual or UPI entries that look like human names (2-3 words, no business suffix)
    final name = t.name.trim();
    if (name.isEmpty) return null;
    final isBusiness = RegExp(
      r'\b(pvt|ltd|store|mart|swiggy|zomato|amazon|flipkart|uber|ola|rapido|blinkit|zepto|upi|imps|neft|atm)\b',
      caseSensitive: false,
    ).hasMatch(name);
    if (!isBusiness && name.split(RegExp(r'\s+')).length <= 3) {
      return name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('People & Hisaab'),
        actions: [
          IconButton(
            tooltip: _sortNewestFirst ? 'Newest First' : 'Oldest First',
            icon: Icon(_sortNewestFirst ? Icons.arrow_downward : Icons.arrow_upward),
            onPressed: () => setState(() => _sortNewestFirst = !_sortNewestFirst),
          ),
        ],
      ),
      body: FutureBuilder<List<Transaction>>(
        future: database.getAllTransactions(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final people = _groupByPerson(snapshot.data!);
          if (people.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Abhi kisi person ka transaction nahi mila.\nJaise hi kisi dost ya vyakti ko UPI/Bank transfer hoga, unka album yahan dikhega.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final activePerson = people.firstWhere(
            (p) => p.name == _selectedPerson,
            orElse: () => people.first,
          );

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Person search karein...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    isDense: true,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

              // Google Photos style Horizontal People Avatars
              SizedBox(
                height: 108,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: people.length,
                  itemBuilder: (context, index) {
                    final person = people[index];
                    final isSelected = person.name == activePerson.name;
                    final initials = person.name
                        .split(' ')
                        .where((w) => w.isNotEmpty)
                        .take(2)
                        .map((w) => w[0].toUpperCase())
                        .join();

                    return GestureDetector(
                      onTap: () => setState(() => _selectedPerson = person.name),
                      child: Container(
                        width: 82,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 28,
                                backgroundColor: isSelected
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.surfaceContainerHighest,
                                child: Text(
                                  initials,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              person.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const Divider(height: 1),

              // Selected Person Summary Card (Total Sent, Received, Net)
              Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statCol('Diya (Sent)', currencyFmt.format(activePerson.totalSent), Colors.redAccent),
                    _statCol('Liya (Received)', currencyFmt.format(activePerson.totalReceived), Colors.green),
                    _statCol(
                      'Net Hisaab',
                      '${activePerson.netBalance >= 0 ? '+' : '-'}${currencyFmt.format(activePerson.netBalance.abs())}',
                      activePerson.netBalance >= 0 ? Colors.green : Colors.orange,
                    ),
                  ],
                ),
              ),

              // Filtered Transactions for ONLY this person
              Expanded(
                child: ListView.separated(
                  itemCount: activePerson.transactions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, i) {
                    final txn = activePerson.transactions[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (txn.income ? Colors.green : Colors.redAccent).withOpacity(0.12),
                        child: Icon(
                          txn.income ? Icons.south_west : Icons.north_east,
                          color: txn.income ? Colors.green : Colors.redAccent,
                          size: 18,
                        ),
                      ),
                      title: Text(txn.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${DateFormat('dd MMM yyyy, hh:mm a').format(txn.dateCreated)}\n${txn.note}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        '${txn.income ? '+' : '-'}${currencyFmt.format(txn.amount.abs())}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: txn.income ? Colors.green : Colors.redAccent,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

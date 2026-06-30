import 'package:flutter/material.dart';
import '../services/sync_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncSummary? _summary;
  bool _isLoading = true;
  bool _isSyncing = false;
  
  double _currentProgress = 0.0;
  String _currentMessage = 'Listo para sincronizar';
  final List<String> _syncLogs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoading = true);
    final summary = await SyncService.instance.getPendingCount();
    setState(() {
      _summary = summary;
      _isLoading = false;
    });
  }

  void _runSync() {
    setState(() {
      _isSyncing = true;
      _currentProgress = 0.0;
      _syncLogs.clear();
      _syncLogs.add('Iniciando proceso de sincronización...');
    });

    SyncService.instance.syncNow().listen(
      (progressEvent) {
        setState(() {
          _currentProgress = progressEvent.progress;
          _currentMessage = progressEvent.message;
          _syncLogs.add(progressEvent.message);
        });

        // Scroll logs to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });

        if (progressEvent.isCompleted || progressEvent.hasError) {
          setState(() {
            _isSyncing = false;
          });
          _loadSummary();
        }
      },
      onError: (err) {
        setState(() {
          _isSyncing = false;
          _currentMessage = 'Error inesperado durante la sincronización';
          _syncLogs.add('ERROR: $err');
        });
        _loadSummary();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _summary?.totalPending ?? 0;
    final isPending = pendingCount > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBE7),
      appBar: AppBar(
        title: const Text('Sincronización', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.green[800],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Header Card
                  Card(
                    elevation: 2,
                    color: isPending ? Colors.orange[50] : Colors.green[50],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Icon(
                            isPending ? Icons.sync_problem : Icons.cloud_done,
                            size: 64,
                            color: isPending ? Colors.orange[800] : Colors.green[800],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isPending ? 'Datos Pendientes de Sincronizar' : 'Predio al Día / Sincronizado',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: isPending ? Colors.orange[900] : Colors.green[900],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isPending
                                ? 'Tienes elementos capturados sin conexión en campo. Sincronízalos cuando tengas señal estable para respaldarlos en la nube.'
                                : 'Todos tus puntos de interés, parcelas y fotografías están guardados de forma segura en los servidores principales.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Pending Counts breakdown
                  if (isPending)
                    Card(
                      elevation: 1,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Column(
                          children: [
                            if (_summary!.pendingFarms > 0) ...[
                              _buildCountRow('Fincas pendientes:', _summary!.pendingFarms),
                              const Divider(),
                            ],
                            if (_summary!.pendingPolygons > 0) ...[
                              _buildCountRow('Parcelas / Lotes pendientes:', _summary!.pendingPolygons),
                              const Divider(),
                            ],
                            if (_summary!.pendingPoints > 0) ...[
                              _buildCountRow('Puntos de interés pendientes:', _summary!.pendingPoints),
                              const Divider(),
                            ],
                            if (_summary!.pendingAnimals > 0) ...[
                              _buildCountRow('Animales pendientes:', _summary!.pendingAnimals),
                              const Divider(),
                            ],
                            if (_summary!.pendingAlerts > 0) ...[
                              _buildCountRow('Alertas de geocercas pendientes:', _summary!.pendingAlerts),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Sync Progress Indicator
                  if (_isSyncing || _syncLogs.isNotEmpty) ...[
                    Text(
                      _currentMessage,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _currentProgress,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.green[800]!),
                        minHeight: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Terminal style Log panel
                    Expanded(
                      child: Card(
                        color: Colors.grey[950],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount: _syncLogs.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Text(
                                  _syncLogs[index],
                                  style: const TextStyle(
                                    color: Colors.lightGreenAccent,
                                    fontFamily: 'Courier',
                                    fontSize: 11,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else
                    const Spacer(),

                  // Sync Actions
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPending ? Colors.green[800] : Colors.grey[400],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: isPending ? 3 : 0,
                    ),
                    onPressed: (isPending && !_isSyncing) ? _runSync : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_isSyncing ? Icons.sync : Icons.cloud_upload),
                        const SizedBox(width: 8),
                        Text(
                          _isSyncing ? 'SINCRONIZANDO...' : 'SINCRONIZAR AHORA',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildCountRow(String label, int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange[800],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

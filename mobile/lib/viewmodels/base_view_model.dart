import 'package:flutter/foundation.dart';

/// Classe base per tutti i ViewModel dell'architettura MVVM di FantaEventi.
///
/// Fornisce la gestione reattiva nativa di:
/// - Stato di caricamento (`isLoading`)
/// - Messaggi di errore (`errorMessage`, `hasError`)
/// - Ciclo di vita sicuro con protezione automatica da memory leak (`_disposed`)
abstract class BaseViewModel extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  bool _disposed = false;

  /// Indica se un'operazione asincrona è attualmente in corso
  bool get isLoading => _isLoading;

  /// Restituisce l'eventuale messaggio di errore riscontrato
  String? get errorMessage => _errorMessage;

  /// True se è presente un messaggio di errore non nullo e non vuoto
  bool get hasError => _errorMessage != null && _errorMessage!.trim().isNotEmpty;

  /// Indica se il ViewModel è già stato distrutto (disposed)
  bool get isDisposed => _disposed;

  /// Aggiorna lo stato di caricamento e notifica la UI solo se il valore cambia
  void setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  /// Imposta un messaggio di errore e notifica i widget in ascolto
  void setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  /// Rimuove qualsiasi errore memorizzato e notifica la UI
  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  /// Sovrascrittura protetta: impedisce chiamate a notifyListeners()
  /// se il widget/ViewModel è già stato deallocato (es. schermata chiusa durante un Future)
  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api_service.dart';

class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  static const String kNoAdsMonthlyProductId = 'no_ads_monthly';

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  ProductDetails? _noAdsProduct;
  bool _storeAvailable = false;
  bool _isProcessing = false;
  String? _lastStatusMessage;
  bool _lastStatusIsError = false;

  ProductDetails? get noAdsProduct => _noAdsProduct;
  bool get storeAvailable => _storeAvailable;
  bool get isProcessing => _isProcessing;
  String? get lastStatusMessage => _lastStatusMessage;
  bool get lastStatusIsError => _lastStatusIsError;

  String get displayPrice => _noAdsProduct?.price ?? '2,49 €';

  Future<void> initialize() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (_purchaseSubscription != null) return;

    try {
      _storeAvailable = await InAppPurchase.instance.isAvailable();
      if (!_storeAvailable) return;

      _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
        _onPurchaseUpdates,
        onError: (Object err) {
          _isProcessing = false;
          _lastStatusIsError = true;
          _lastStatusMessage = 'Errore comunicazione Store: $err';
          notifyListeners();
        },
      );

      await refreshProducts();
    } catch (e) {
      debugPrint('SubscriptionService initialize notice: $e');
    }
  }

  Future<void> refreshProducts() async {
    if (!_storeAvailable) return;
    try {
      final response = await InAppPurchase.instance.queryProductDetails({kNoAdsMonthlyProductId});
      if (response.productDetails.isNotEmpty) {
        _noAdsProduct = response.productDetails.first;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('SubscriptionService refreshProducts notice: $e');
    }
  }

  void clearStatusMessage() {
    _lastStatusMessage = null;
    _lastStatusIsError = false;
  }

  Future<bool> buyNoAdsMonthly() async {
    clearStatusMessage();
    if (!_storeAvailable) {
      _lastStatusIsError = true;
      _lastStatusMessage =
          'Lo Store pagamenti (Google Play / App Store) non è raggiungibile su questo dispositivo.';
      notifyListeners();
      return false;
    }

    if (_noAdsProduct == null) {
      await refreshProducts();
    }

    if (_noAdsProduct == null) {
      _lastStatusIsError = true;
      _lastStatusMessage =
          'L\'abbonamento VIP No-Ads (2,49 €/mese) si attiverà automaticamente non appena FantaEventi sarà pubblicata sullo Store ufficiale!';
      notifyListeners();
      return false;
    }

    _isProcessing = true;
    notifyListeners();

    try {
      final param = PurchaseParam(productDetails: _noAdsProduct!);
      final started = await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
      if (!started) {
        _isProcessing = false;
        notifyListeners();
      }
      return started;
    } catch (e) {
      _isProcessing = false;
      _lastStatusIsError = true;
      _lastStatusMessage = 'Impossibile avviare il pagamento: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> restorePurchases() async {
    clearStatusMessage();
    if (!_storeAvailable) {
      _lastStatusIsError = true;
      _lastStatusMessage = 'Store non disponibile su questo dispositivo.';
      notifyListeners();
      return;
    }

    _isProcessing = true;
    notifyListeners();

    try {
      await InAppPurchase.instance.restorePurchases();
      await Future.delayed(const Duration(seconds: 2));
      if (_isProcessing) {
        _isProcessing = false;
        if (ApiService().currentUser?.isNoAds == true) {
          _lastStatusIsError = false;
          _lastStatusMessage = 'Abbonamento VIP No-Ads ripristinato con successo!';
        } else {
          _lastStatusIsError = false;
          _lastStatusMessage = 'Nessun abbonamento attivo trovato sul tuo account Store.';
        }
        notifyListeners();
      }
    } catch (e) {
      _isProcessing = false;
      _lastStatusIsError = true;
      _lastStatusMessage = 'Errore durante il ripristino acquisti.';
      notifyListeners();
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        _isProcessing = true;
        notifyListeners();
      } else if (purchase.status == PurchaseStatus.canceled) {
        _isProcessing = false;
        _lastStatusIsError = false;
        _lastStatusMessage = 'Operazione annullata.';
        notifyListeners();
      } else if (purchase.status == PurchaseStatus.error) {
        _isProcessing = false;
        _lastStatusIsError = true;
        _lastStatusMessage = purchase.error?.message ?? 'Pagamento non completato.';
        notifyListeners();
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        if (purchase.pendingCompletePurchase) {
          try {
            await InAppPurchase.instance.completePurchase(purchase);
          } catch (_) {}
        }

        final platformName = Platform.isIOS ? 'ios' : 'android';
        await ApiService().aggiornaAbbonamentoNoAds(
          attivo: true,
          productId: purchase.productID,
          platform: platformName,
          purchaseId: purchase.purchaseID ?? '',
        );

        _isProcessing = false;
        _lastStatusIsError = false;
        _lastStatusMessage = '👑 Benvenuto in FantaEventi VIP! Tutte le pubblicità sono state rimosse.';
        notifyListeners();
      }
    }
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'api_service.dart';
import '../widgets/app_toast.dart';

class AdMobService {
  AdMobService._();
  static final AdMobService instance = AdMobService._();

  /// IMPORTANTE: Mantenere `true` durante i test pre-pubblicazione sui propri dispositivi
  /// per visualizzare al 100% gli annunci ufficiali "Test Ad" ed evitare click invalidi sull'account AdMob.
  /// Impostare a `false` al momento della generazione del pacchetto finale firmato per Play Store / App Store.
  static const bool useGoogleSampleTestUnits = true;

  // --- CODICI UFFICIALI DI PRODUZIONE FANTAEVENTI (Google AdMob) ---
  static const String _prodAndroidBannerId = 'ca-app-pub-6019738318234363/4686594622';
  static const String _prodAndroidInterstitialId = 'ca-app-pub-6019738318234363/7301470475';
  static const String _prodAndroidRewardedId = 'ca-app-pub-6019738318234363/2348526692';

  static const String _prodIosBannerId = 'ca-app-pub-6019738318234363/4483735446';
  static const String _prodIosInterstitialId = 'ca-app-pub-6019738318234363/5465644626';
  static const String _prodIosRewardedId = 'ca-app-pub-6019738318234363/1262354934';

  // --- CODICI CAMPIONE UFFICIALI GOOGLE PER TEST SICURO ---
  static const String _testAndroidBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testAndroidInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const String _testAndroidRewardedId = 'ca-app-pub-3940256099942544/5224354917';

  static const String _testIosBannerId = 'ca-app-pub-3940256099942544/2934735716';
  static const String _testIosInterstitialId = 'ca-app-pub-3940256099942544/4411468910';
  static const String _testIosRewardedId = 'ca-app-pub-3940256099942544/1712485313';

  static bool get isSupportedPlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static String get bannerAdUnitId {
    if (!isSupportedPlatform) return '';
    if (Platform.isAndroid) {
      return useGoogleSampleTestUnits ? _testAndroidBannerId : _prodAndroidBannerId;
    }
    return useGoogleSampleTestUnits ? _testIosBannerId : _prodIosBannerId;
  }

  static String get interstitialAdUnitId {
    if (!isSupportedPlatform) return '';
    if (Platform.isAndroid) {
      return useGoogleSampleTestUnits ? _testAndroidInterstitialId : _prodAndroidInterstitialId;
    }
    return useGoogleSampleTestUnits ? _testIosInterstitialId : _prodIosInterstitialId;
  }

  static String get rewardedAdUnitId {
    if (!isSupportedPlatform) return '';
    if (Platform.isAndroid) {
      return useGoogleSampleTestUnits ? _testAndroidRewardedId : _prodAndroidRewardedId;
    }
    return useGoogleSampleTestUnits ? _testIosRewardedId : _prodIosRewardedId;
  }

  bool _isSdkInitialized = false;
  bool _isInitializing = false;
  final ValueNotifier<bool> sdkReadyNotifier = ValueNotifier<bool>(false);

  InterstitialAd? _interstitialAd;
  bool _isLoadingInterstitial = false;
  DateTime? _lastInterstitialShownAt;

  RewardedAd? _rewardedAd;
  bool _isLoadingRewarded = false;

  /// Richiede il consenso europeo GDPR (UMP) se dovuto e inizializza l'SDK Google Mobile Ads
  Future<void> initializeAndGatherConsent() async {
    if (!isSupportedPlatform || _isSdkInitialized || _isInitializing) return;
    _isInitializing = true;

    try {
      final params = ConsentRequestParameters();
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
              if (formError != null) {
                debugPrint('UMP ConsentForm notice: ${formError.message}');
              }
            });
          } catch (e) {
            debugPrint('UMP loadAndShow notice: $e');
          }
          await _startMobileAdsSdk();
        },
        (FormError error) async {
          debugPrint('UMP requestConsentInfoUpdate notice: ${error.message}');
          await _startMobileAdsSdk();
        },
      );
    } catch (e) {
      debugPrint('AdMob initializeAndGatherConsent notice: $e');
      await _startMobileAdsSdk();
    }
  }

  Future<void> _startMobileAdsSdk() async {
    if (_isSdkInitialized) {
      _isInitializing = false;
      return;
    }
    try {
      final canRequest = await ConsentInformation.instance.canRequestAds();
      if (!canRequest) {
        // Anche se canRequestAds è false al primo check offline, inizializziamo comunque in fallback
        debugPrint('AdMob canRequestAds false, inizializzazione SDK standard...');
      }
      await MobileAds.instance.initialize();
      _isSdkInitialized = true;
      sdkReadyNotifier.value = true;
      _preloadInterstitial();
      _preloadRewarded();
    } catch (e) {
      debugPrint('MobileAds.initialize notice: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// Riapre su richiesta dell'utente il pannello ufficiale GDPR per modificare/revocare il consenso annunci
  Future<void> showPrivacyOptionsForm(BuildContext context) async {
    if (!isSupportedPlatform) return;
    try {
      final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      if (status != PrivacyOptionsRequirementStatus.required) {
        if (context.mounted) {
          AppToast.showInfo(
            context,
            'Preferenze Privacy Annunci 🛡️',
            'Al momento non sono richieste ulteriori impostazioni di consenso per la tua area geografica.',
          );
        }
        return;
      }

      await ConsentForm.showPrivacyOptionsForm((formError) {
        if (!context.mounted) return;
        if (formError != null) {
          AppToast.showWarning(
            context,
            'Preferenze Privacy',
            'Impossibile aprire il modulo in questo momento. Riprova tra poco.',
          );
        } else {
          AppToast.showSuccess(
            context,
            'Preferenze Aggiornate ✅',
            'Le tue scelte sulla privacy pubblicitaria sono state salvate.',
          );
        }
      });
    } catch (_) {
      if (context.mounted) {
        AppToast.showInfo(
          context,
          'Preferenze Privacy Annunci 🛡️',
          'Le tue preferenze privacy sono già aggiornate.',
        );
      }
    }
  }

  void _preloadInterstitial() {
    if (!isSupportedPlatform || !_isSdkInitialized || _isLoadingInterstitial || _interstitialAd != null) return;
    if (ApiService().currentUser?.isNoAds == true) return;

    final unitId = interstitialAdUnitId;
    if (unitId.isEmpty) return;

    _isLoadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _isLoadingInterstitial = false;
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (err) {
          _isLoadingInterstitial = false;
          _interstitialAd = null;
          debugPrint('Interstitial preload notice: ${err.message}');
        },
      ),
    );
  }

  /// Mostra l'annuncio Interstitial dopo la creazione di un evento (max 1 ogni 5 minuti, mai per utenti VIP No-Ads)
  Future<void> showInterstitialAfterEventCreation() async {
    if (!isSupportedPlatform) return;
    if (ApiService().currentUser?.isNoAds == true) return;

    final now = DateTime.now();
    if (_lastInterstitialShownAt != null && now.difference(_lastInterstitialShownAt!).inMinutes < 5) {
      return;
    }

    final ad = _interstitialAd;
    if (ad == null) {
      _preloadInterstitial();
      return;
    }

    _interstitialAd = null;
    _lastInterstitialShownAt = now;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (adObj) {
        adObj.dispose();
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (adObj, err) {
        adObj.dispose();
        _preloadInterstitial();
      },
    );

    try {
      await ad.show();
    } catch (_) {
      ad.dispose();
    }
  }

  void _preloadRewarded() {
    if (!isSupportedPlatform || !_isSdkInitialized || _isLoadingRewarded || _rewardedAd != null) return;
    final unitId = rewardedAdUnitId;
    if (unitId.isEmpty) return;

    _isLoadingRewarded = true;
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _isLoadingRewarded = false;
          _rewardedAd = ad;
        },
        onAdFailedToLoad: (err) {
          _isLoadingRewarded = false;
          _rewardedAd = null;
          debugPrint('Rewarded preload notice: ${err.message}');
        },
      ),
    );
  }

  /// Mostra uno spot video con ricompensa (+100 XP). Ritorna `true` solo se il video è stato visto fino al premio.
  Future<bool> showRewardedVideoForXp({
    required void Function(String message) onError,
  }) async {
    if (!isSupportedPlatform) {
      onError('Gli annunci video sono disponibili solo su smartphone Android e iOS.');
      return false;
    }

    if (!_isSdkInitialized) {
      await _startMobileAdsSdk();
    }

    RewardedAd? ad = _rewardedAd;
    if (ad == null) {
      final completer = Completer<RewardedAd?>();
      RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (loadedAd) => completer.complete(loadedAd),
          onAdFailedToLoad: (err) {
            debugPrint('Rewarded on-demand load failed: ${err.message}');
            completer.complete(null);
          },
        ),
      );
      ad = await completer.future.timeout(const Duration(seconds: 8), onTimeout: () => null);
    } else {
      _rewardedAd = null;
    }

    if (ad == null) {
      _preloadRewarded();
      onError('Nessuno spot disponibile in questo istante. Riprova tra qualche secondo!');
      return false;
    }

    final rewardCompleter = Completer<bool>();
    bool earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (adObj) {
        adObj.dispose();
        _preloadRewarded();
        if (!rewardCompleter.isCompleted) {
          rewardCompleter.complete(earned);
        }
      },
      onAdFailedToShowFullScreenContent: (adObj, err) {
        adObj.dispose();
        _preloadRewarded();
        onError('Impossibile riprodurre lo spot video. Riprova tra poco.');
        if (!rewardCompleter.isCompleted) {
          rewardCompleter.complete(false);
        }
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (AdWithoutView adView, RewardItem rewardItem) {
          earned = true;
        },
      );
      return await rewardCompleter.future.timeout(const Duration(minutes: 2), onTimeout: () => earned);
    } catch (_) {
      ad.dispose();
      _preloadRewarded();
      onError('Errore durante la riproduzione dello spot.');
      return false;
    }
  }
}

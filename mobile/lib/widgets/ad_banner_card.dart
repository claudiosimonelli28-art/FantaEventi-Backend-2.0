import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/admob_service.dart';
import '../services/api_service.dart';

/// Card sponsorizzata integrata nella lista eventi (mai sovrapposta al pulsante + FAB e 100% conforme alle policy Google AdMob)
class AdBannerCard extends StatefulWidget {
  final VoidCallback onTapNoAds;

  const AdBannerCard({
    super.key,
    required this.onTapNoAds,
  });

  @override
  State<AdBannerCard> createState() => _AdBannerCardState();
}

class _AdBannerCardState extends State<AdBannerCard> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _isLoadingAd = false;

  @override
  void initState() {
    super.initState();
    ApiService().noAdsNotifier.addListener(_onNoAdsChanged);
    AdMobService.instance.sdkReadyNotifier.addListener(_onSdkReady);
    _tryLoadBanner();
  }

  void _onNoAdsChanged() {
    if (!mounted) return;
    if (ApiService().noAdsNotifier.value) {
      _disposeBanner();
      setState(() {});
    } else {
      _tryLoadBanner();
    }
  }

  void _onSdkReady() {
    if (!mounted) return;
    if (AdMobService.instance.sdkReadyNotifier.value && !_isLoaded) {
      _tryLoadBanner();
    }
  }

  void _tryLoadBanner() {
    if (!AdMobService.isSupportedPlatform) return;
    if (ApiService().noAdsNotifier.value || ApiService().currentUser?.isNoAds == true) return;
    if (!AdMobService.instance.sdkReadyNotifier.value) return;
    if (_isLoaded || _isLoadingAd || _bannerAd != null) return;

    final unitId = AdMobService.bannerAdUnitId;
    if (unitId.isEmpty) return;

    _isLoadingAd = true;
    final ad = BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          _isLoadingAd = false;
          if (!mounted || ApiService().noAdsNotifier.value) {
            loadedAd.dispose();
            return;
          }
          setState(() {
            _bannerAd = loadedAd as BannerAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (failedAd, error) {
          _isLoadingAd = false;
          failedAd.dispose();
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _isLoaded = false;
            });
          }
        },
      ),
    );
    ad.load();
  }

  void _disposeBanner() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
    _isLoadingAd = false;
  }

  @override
  void dispose() {
    ApiService().noAdsNotifier.removeListener(_onNoAdsChanged);
    AdMobService.instance.sdkReadyNotifier.removeListener(_onSdkReady);
    _disposeBanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ApiService().noAdsNotifier.value ||
        ApiService().currentUser?.isNoAds == true ||
        !_isLoaded ||
        _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.campaign_outlined, size: 14, color: Color(0xFF64748B)),
                  const SizedBox(width: 5),
                  Text(
                    'ANNUNCIO SPONSORIZZATO',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: widget.onTapNoAds,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFACC15).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    '🚫 No Ads',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFACC15),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          ),
        ],
      ),
    );
  }
}

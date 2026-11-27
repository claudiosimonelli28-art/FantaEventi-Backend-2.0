import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/subscription_service.dart';
import 'app_toast.dart';
import 'founder_badge.dart';

class NoAdsVipModal extends StatefulWidget {
  const NoAdsVipModal({super.key});

  static Future<void> mostra(BuildContext context) async {
    await SubscriptionService.instance.initialize();
    SubscriptionService.instance.clearStatusMessage();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NoAdsVipModal(),
    );
  }

  @override
  State<NoAdsVipModal> createState() => _NoAdsVipModalState();
}

class _NoAdsVipModalState extends State<NoAdsVipModal> {
  final SubscriptionService _subService = SubscriptionService.instance;
  final ApiService _apiService = ApiService();
  bool _isAdminToggling = false;

  @override
  void initState() {
    super.initState();
    _subService.addListener(_onSubChanged);
  }

  void _onSubChanged() {
    if (!mounted) return;
    final msg = _subService.lastStatusMessage;
    if (msg != null && msg.isNotEmpty) {
      if (_subService.lastStatusIsError) {
        AppToast.showInfo(context, 'Info Abbonamento Store 👑', msg, const Duration(seconds: 5));
      } else {
        AppToast.showSuccess(context, 'VIP No-Ads 👑', msg, const Duration(seconds: 4));
      }
      _subService.clearStatusMessage();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _subService.removeListener(_onSubChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curUser = _apiService.currentUser;
    final bool isVipActive = curUser?.isNoAds == true;
    final bool isAdminCloud = curUser != null && FounderBadge.isFounder(curUser.nickname);
    final String priceStr = _subService.displayPrice;

    return Container(
      padding: EdgeInsets.only(
        left: 22,
        right: 22,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 22,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Color(0xFFFACC15), width: 1.5),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF475569),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFACC15).withValues(alpha: 0.25),
                        const Color(0xFF9333EA).withValues(alpha: 0.25),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFACC15), width: 1.5),
                  ),
                  child: const Text('👑', style: TextStyle(fontSize: 26)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FantaEventi VIP — No Ads',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        isVipActive
                            ? 'Abbonamento attivo sul tuo profilo ✨'
                            : 'Gioca senza interruzioni pubblicitarie',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: isVipActive ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                          fontWeight: isVipActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                children: [
                  _buildBenefitRow(
                    '🚫',
                    'Zero Banner e Zero Spot',
                    'Rimuove tutti i banner nel feed e gli annunci a schermo intero dopo la creazione degli eventi.',
                  ),
                  const SizedBox(height: 12),
                  _buildBenefitRow(
                    '👑',
                    'Badge Esclusivo "VIP No-Ads"',
                    'Sblocca la targhetta dorata VIP visibile nella tua bacheca giocatore.',
                  ),
                  const SizedBox(height: 12),
                  _buildBenefitRow(
                    '🎬',
                    'Bonus +100 XP Sempre Disponibili',
                    'Se vuoi salire più velocemente di livello, i video premio facoltativi nel profilo restano comunque a tua disposizione!',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (isVipActive)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'SEI GIÀ UTENTE VIP NO-ADS 👑',
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF34D399),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _subService.isProcessing
                      ? null
                      : () async {
                          await _subService.buyNoAdsMonthly();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFACC15),
                    foregroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 6,
                  ),
                  child: _subService.isProcessing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0F172A)),
                        )
                      : Text(
                          'ABBONATI ORA — $priceStr / MESE',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                ),
              ),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: _subService.isProcessing
                    ? null
                    : () async {
                        await _subService.restorePurchases();
                      },
                icon: const Icon(Icons.restore_rounded, size: 17, color: Color(0xFFCBD5E1)),
                label: Text(
                  'Ripristina acquisti precedenti',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFCBD5E1),
                  ),
                ),
              ),
            ),
            Text(
              'Abbonamento mensile gestito in sicurezza tramite Google Play / Apple ID. Puoi disdire il rinnovo automatico in qualsiasi momento dalle impostazioni dello Store.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                height: 1.35,
                color: const Color(0xFF64748B),
              ),
            ),
            if (isAdminCloud) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF9333EA).withValues(alpha: 0.6)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.science_rounded, color: Color(0xFFC084FC), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Test Admin (Visibile solo a Cloud)',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFC084FC),
                            ),
                          ),
                          Text(
                            'Simula attivazione/disattivazione VIP No-Ads',
                            style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isVipActive,
                      activeThumbColor: const Color(0xFFFACC15),
                      onChanged: _isAdminToggling
                          ? null
                          : (val) async {
                              setState(() => _isAdminToggling = true);
                              final ok = await _apiService.aggiornaAbbonamentoNoAds(
                                attivo: val,
                                platform: 'admin_preview',
                              );
                              if (!mounted) return;
                              setState(() => _isAdminToggling = false);
                              if (ok && context.mounted) {
                                AppToast.showSuccess(
                                  context,
                                  val ? 'VIP No-Ads Attivato 👑' : 'Pubblicità Riattivate 📺',
                                  val
                                      ? 'Tutti i banner sono stati nascosti e hai ricevuto il badge VIP!'
                                      : 'Modalità standard con annunci ripristinata.',
                                );
                              }
                            },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitRow(String emoji, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFFACC15),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  height: 1.4,
                  color: const Color(0xFFCBD5E1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

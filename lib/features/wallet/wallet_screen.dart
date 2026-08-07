import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/core/utils/price_formatter.dart';

/// شاشة محفظة الراكب.
///
/// تعرض الرصيد من `GET /wallet/balance` وقائمة آخر المعاملات من
/// `GET /wallet/transactions` — كلها من الـ Backend فقط (لا يوجد رصيد وهمي).
/// زر «شحن» يفتح رابط الدفع (Kashier) من `POST /wallet/top-up` في المتصفح،
/// والرصيد يُحدَّث تلقائياً بعد نجاح الدفع عبر Webhook.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _balance;
  List<dynamic> _transactions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final balance = await ApiService.instance.getWalletBalance();
      Map<String, dynamic> tx = const {};
      try {
        tx = await ApiService.instance.getWalletTransactions();
      } catch (e) {
        logWarning('WalletScreen', 'getWalletTransactions failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _transactions = (tx['transactions'] as List?) ?? const [];
        _loading = false;
      });
    } catch (e) {
      logError('WalletScreen', 'getWalletBalance failed: $e', e);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل المحفظة. تحقق من اتصالك ثم أعد المحاولة.';
      });
    }
  }

  double get _balanceValue => parsePrice(_balance?['balance']);

  /// يفتح حوار اختيار مبلغ الشحن ثم يستدعي `POST /wallet/top-up` ويفتح رابط
  /// الدفع في المتصفح. لا يكسر الشاشة عند أي فشل — يُعرض «الشحن غير متاح».
  Future<void> _topUp() async {
    final amount = await _pickTopUpAmount();
    if (amount == null || !mounted) return;
    try {
      final resp = await ApiService.instance.topUpWallet(amount: amount);
      final paymentUrl =
          (resp['paymentUrl'] as String?) ??
          (resp['sessionUrl'] as String?) ??
          (resp['checkoutUrl'] as String?);
      if (paymentUrl == null || paymentUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر إنشاء رابط الدفع، حاول مرة أخرى'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
        return;
      }
      final ok = await launchUrl(
        Uri.parse(paymentUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح رابط الدفع'),
            backgroundColor: AppColors.warning,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('بعد إتمام الدفع سيتم تحديث رصيدك تلقائياً'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      logError('WalletScreen', 'topUp failed: $e', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الشحن غير متاح حالياً، حاول لاحقاً'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }

  Future<double?> _pickTopUpAmount() {
    final amounts = [50.0, 100.0, 200.0, 500.0];
    return showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppColors.darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXxl),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('شحن المحفظة', style: AppTextStyles.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              for (final a in amounts)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: SizedBox(
                    width: double.infinity,
                    height: AppSpacing.buttonHeightMd,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, a),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryGreen,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                      ),
                      child: Text(
                        formatEGP(a),
                        style: AppTextStyles.titleSmall,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'سيتم تحويلك لبوابة الدفع الآمنة (Kashier)',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('المحفظة'),
        backgroundColor: AppColors.darkBg,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryGreen,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _buildBalanceCard(),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: AppSpacing.buttonHeightMd,
            child: FilledButton.icon(
              onPressed: _topUp,
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('شحن الرصيد'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: AppColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('آخر المعاملات', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.md),
          if (_transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text(
                  'لا توجد معاملات بعد',
                  style: AppTextStyles.bodyMedium,
                ),
              ),
            )
          else
            ..._transactions.map(
              (t) => _TransactionTile(tx: t is Map ? t : const {}),
            ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryContainer, AppColors.cardBg],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('رصيد المحفظة', style: AppTextStyles.bodySmall),
          const SizedBox(height: AppSpacing.md),
          Text(
            formatEGP(_balanceValue),
            style: AppTextStyles.displaySmall?.copyWith(
              color: AppColors.primaryGreen,
            ),
          ),
          if ((_balance?['fullName'] as String?)?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _balance!['fullName'] as String,
              style: AppTextStyles.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// صف معاملة واحدة: أيقونة + عنوان عربي للنوع + وصف + المبلغ + الحالة.
class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});

  final Map<dynamic, dynamic> tx;

  String get _typeLabel {
    switch (tx['type']) {
      case 'TOPUP':
        return 'شحن الرصيد';
      case 'WITHDRAWAL':
        return 'سحب';
      case 'RIDE_DEDUCTION':
        return 'خصم الرحلة';
      case 'RIDE_HOLD':
        return 'تحصيل مؤقت للرحلة';
      case 'RIDE_REFUND':
        return 'استرداد الرحلة';
      case 'DRIVER_EARNING':
        return 'أرباح الكابتن';
      case 'COMMISSION':
        return 'عمولة';
      case 'COMMISSION_REFUND':
        return 'استرداد عمولة';
      case 'LATE_FEE':
        return 'رسوم تأخير';
      case 'LATE_FEE_CREDIT':
        return 'خصم رسوم تأخير';
      default:
        return 'معاملة';
    }
  }

  IconData get _icon {
    switch (tx['type']) {
      case 'TOPUP':
        return Icons.add_card_rounded;
      case 'WITHDRAWAL':
        return Icons.account_balance_wallet_rounded;
      case 'RIDE_REFUND':
      case 'COMMISSION_REFUND':
      case 'LATE_FEE_CREDIT':
        return Icons.undo_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  String get _statusLabel {
    switch (tx['status']) {
      case 'HELD':
        return 'معلق';
      case 'SETTLED':
      case 'COMPLETED':
        return 'مكتمل';
      case 'RELEASED':
        return 'مُعاد';
      default:
        return '—';
    }
  }

  String get _date {
    final raw = tx['createdAt'];
    if (raw is String && raw.isNotEmpty) {
      final dt = DateTime.tryParse(raw)?.toLocal();
      if (dt != null) {
        final h = dt.hour.toString().padLeft(2, '0');
        final m = dt.minute.toString().padLeft(2, '0');
        return '${dt.day}/${dt.month}/${dt.year} · $h:$m';
      }
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final amount = parsePrice(tx['amount']);
    final positive =
        tx['type'] == 'TOPUP' ||
        tx['type'] == 'RIDE_REFUND' ||
        tx['type'] == 'COMMISSION_REFUND' ||
        tx['type'] == 'LATE_FEE_CREDIT' ||
        tx['type'] == 'DRIVER_EARNING';
    final desc = tx['description'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(
              _icon,
              color: AppColors.primaryGreen,
              size: AppSpacing.iconMd,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_typeLabel, style: AppTextStyles.titleSmall),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.xxs),
                Text(_date, style: AppTextStyles.labelSmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${positive ? '+' : '-'}${formatEGP(amount.abs())}',
                style: AppTextStyles.titleSmall?.copyWith(
                  color: positive
                      ? AppColors.primaryGreen
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(_statusLabel, style: AppTextStyles.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

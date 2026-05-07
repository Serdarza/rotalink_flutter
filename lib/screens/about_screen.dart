import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

/// Marka içeriği: Kotlin [dialog_about] metinleri.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  /// Doldurulduğunda «Bağlantılar» bölümünde ilgili buton gösterilir.
  static const String _linkedInProfileUrl = '';
  static const String _xProfileUrl = '';

  static const String _whoWeAre =
      'Rotalink, yollara gönül vermiş ve sevdikleriyle güvenle seyahat etmek isteyenler için doğmuş bir projedir. '
      'Özellikle kamu personellerimizin; tayin, görev veya tatil yolculuklarında “Nerede güvenle konaklayabilirim?” '
      'sorusuna en hızlı cevabı verebilmek amacıyla geliştirilmiştir.';

  static const String _vision =
      'Amacımız; Türkiye’nin dört bir yanındaki misafirhaneleri ve gezi rotalarını tek bir haritada birleştirmektir. '
      'Tamamen bağımsız bir çabayla tasarlanan Rotalink, sizlerin destekleriyle büyümeye devam edecektir.\n\n'
      'Rotanız hep açık olsun!';

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await canLaunchUrl(uri);
      if (ok) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bağlantı açılamadı.')),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı açılamadı.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Edge-to-edge (ana ekran) açıkken [padding.bottom] 0 kalabiliyor; viewPadding gerçek sistem çubuğunu verir.
    final navBarInset = MediaQuery.viewPaddingOf(context).bottom;
    final showLinksSection =
        _linkedInProfileUrl.isNotEmpty || _xProfileUrl.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.drawerAbout),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: navBarInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Material(
                    elevation: 6,
                    shadowColor: AppColors.primary.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 96,
                        height: 96,
                        color: AppColors.campaignBtnSecondary,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.attractions_outlined,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.drawerSubtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (showLinksSection) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Bağlantılar',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (_linkedInProfileUrl.isNotEmpty)
                          FilledButton.tonalIcon(
                            onPressed: () => _openUrl(context, _linkedInProfileUrl),
                            icon: const Icon(Icons.work_outline, size: 20),
                            label: const Text('LinkedIn'),
                            style: FilledButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              backgroundColor: AppColors.campaignBtnSecondary,
                            ),
                          ),
                        if (_xProfileUrl.isNotEmpty)
                          FilledButton.tonalIcon(
                            onPressed: () => _openUrl(context, _xProfileUrl),
                            icon: const Icon(Icons.chat_bubble_outline, size: 20),
                            label: const Text('X'),
                            style: FilledButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              backgroundColor: AppColors.campaignBtnSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            _SectionCard(
              title: 'Biz kimiz?',
              body: _whoWeAre,
            ),
            _SectionCard(
              title: 'Vizyonumuz',
              body: _vision,
            ),
            _SectionCard(
              title: 'Sosyal medya ve iletişim',
              body:
                  'Geri bildirim ve önerileriniz için uygulama menüsündeki «Öneri Gönder» seçeneğini kullanabilirsiniz.',
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 28 + navBarInset),
              child: Text(
                '— Rotalink Geliştirici Ekibi',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 2,
                color: AppColors.primary,
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

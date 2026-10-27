import 'package:flutter/material.dart';

import '../models/campaign.dart';

/// Rotalink'in kendi katılım duyurusu; kurum kampanyalarından ayrı sunulur.
class CampaignPromotionCard extends StatelessWidget {
  const CampaignPromotionCard({
    super.key,
    required this.campaign,
    required this.onTap,
  });

  final Campaign campaign;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFDC91);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Material(
        color: const Color(0xFF102D3D),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: gold.withValues(alpha: 0.55)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF102D3D), Color(0xFF096575)],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: gold,
                          size: 20,
                        ),
                      ),
                      const Text(
                        'ROTALINK İŞ BİRLİĞİ',
                        style: TextStyle(
                          color: gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    campaign.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (campaign.summary.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      campaign.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFD6EAED),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: gold,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mail_outline_rounded,
                          color: Color(0xFF18343F),
                          size: 17,
                        ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'İş birliğini keşfet',
                            style: TextStyle(
                              color: Color(0xFF18343F),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF18343F),
                          size: 17,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

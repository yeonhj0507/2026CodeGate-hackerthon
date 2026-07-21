import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_colors.dart';
import 'widgets/logo_mark.dart';

/// 생각 지도가 비어 있을 때 전체 화면을 채우는 온보딩(Figma S4).
///
/// 그래프가 비면 우측 도킹 패널도 보여줄 추천/상세/기사 데이터가 없으므로,
/// Figma 시안대로 홈 레이아웃 전체를 이 화면으로 대체한다.
class OnboardingView extends StatelessWidget {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LogoLockup(iconSize: 24, textSize: 16),
            const SizedBox(height: 24),
            SvgPicture.asset(
              'assets/branding/empty_state_illustration.svg',
              width: 300,
              height: 175,
            ),
            const SizedBox(height: 24),
            const Text(
              '아직 생각 지도가 비어 있어요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '크롬 익스텐션으로 기사를 읽고 진단을 마치면,\n생각 지도가 자동으로 만들어져요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textMuted, height: 1.6),
            ),
            const SizedBox(height: 24),
            const Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _StepCard(
                  step: 1,
                  title: '익스텐션 설치·로그인',
                  body: '크롬 익스텐션을 설치하고 같은 계정으로 로그인하세요',
                ),
                _StepCard(
                  step: 2,
                  title: '기사 읽으며 진단',
                  body: '경제 기사를 읽으면 문단마다 질문이 도착해요',
                ),
                _StepCard(
                  step: 3,
                  title: '지도 자동 생성',
                  body: '진단 결과가 자동으로 지도에 반영돼요',
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('크롬 익스텐션은 별도로 배포돼요.')),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.pinkStrong,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              child: const Text('크롬 익스텐션 설치',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.body,
  });

  final int step;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.pinkBgSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '$step',
              style: const TextStyle(
                  color: AppColors.pink,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

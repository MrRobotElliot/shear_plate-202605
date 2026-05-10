import 'package:flutter/material.dart';
import 'package:shear_plate/register_page.dart';

/// Settings screen with top tabs (TabLayout + ViewPager style) and swipeable pages.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '账号'),
              Tab(text: '通用'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AccountTabBody(),
            _GeneralTabBody(),
          ],
        ),
      ),
    );
  }
}

class _AccountTabBody extends StatelessWidget {
  const _AccountTabBody();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(Icons.person, size: 32, color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '未登录',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '登录后可同步剪切板历史（功能待接入）',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('登录功能开发中')),
                            );
                          },
                          child: const Text('登录'),
                        ),
                      ),
                      VerticalDivider(
                        width: 17,
                        thickness: 1,
                        indent: 8,
                        endIndent: 8,
                        color: scheme.outlineVariant,
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (context) => const RegisterPage(),
                              ),
                            );
                          },
                          child: const Text('注册'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('个人资料'),
          enabled: false,
          subtitle: const Text('登录后可用'),
        ),
      ],
    );
  }
}

class _GeneralTabBody extends StatelessWidget {
  const _GeneralTabBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.tune_outlined),
          title: const Text('通用选项'),
          subtitle: const Text('后续可在此添加主题、语言等设置'),
        ),
      ],
    );
  }
}

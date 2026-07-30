import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:provider/provider.dart';
import '../../providers/retro_achievements_provider.dart';
import '../../widgets/confirm_action_dialog.dart';
import '../../widgets/custom_notification.dart';
import '../../responsive.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import '../../services/game_service.dart' show GamepadNavigationManager;
import '../app_screen.dart' show AppNavigation;
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'ra_dashboard.dart';

class RAContent extends StatefulWidget {
  const RAContent({super.key});

  /// Returns whether the selection/scroll actually moved, so the gamepad
  /// handler can suppress the nav sound when repeating against a boundary.
  static bool navigateUp({bool repeat = false}) =>
      _RAContentState.navigateUp(repeat: repeat);

  static bool navigateDown({bool repeat = false}) =>
      _RAContentState.navigateDown(repeat: repeat);

  @override
  State<RAContent> createState() => _RAContentState();
}

class _RAContentState extends State<RAContent> {
  static _RAContentState? _currentInstance;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _apiKeyFocus = FocusNode();
  final ScrollController _dashboardScrollController = ScrollController();

  int _selectedFieldIndex = 0;
  bool _dashboardLogoutSelected = true;
  GamepadNavigation? _gamepadNav;

  @override
  void initState() {
    super.initState();
    _currentInstance = this;
    _dashboardScrollController.addListener(_updateDashboardSelection);
    _initControllerNavigation();
  }

  void _initControllerNavigation() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: _handleNavigateUp,
      onNavigateDown: _handleNavigateDown,
      onSelectItem: _selectCurrent,
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
      isTextFieldFocused: _isAnyFieldFocused,
      onBack: _exitTextEntry,
    );
    _gamepadNav!.initialize();
    GamepadNavigationManager.pushLayer(
      'ra_content',
      onActivate: () => _gamepadNav?.activate(),
      onDeactivate: () => _gamepadNav?.deactivate(),
    );
  }

  bool _moveSelection(int delta) {
    setState(() {
      _selectedFieldIndex = (_selectedFieldIndex + delta + 3) % 3;
    });
    return true;
  }

  void _selectCurrent() {
    final raProvider = context.read<RetroAchievementsProvider>();
    if (raProvider.isConnected) {
      if (_dashboardLogoutSelected) _requestDisconnect();
      return;
    }
    if (_selectedFieldIndex == 0) {
      _usernameFocus.requestFocus();
    } else if (_selectedFieldIndex == 1) {
      _apiKeyFocus.requestFocus();
    } else {
      _connectToRA();
    }
  }

  bool _isAnyFieldFocused() => _usernameFocus.hasFocus || _apiKeyFocus.hasFocus;

  void _exitTextEntry() {
    if (_isAnyFieldFocused()) FocusScope.of(context).unfocus();
  }

  bool _isSelected(int slot) => _selectedFieldIndex == slot;

  void _updateDashboardSelection() {
    if (!_dashboardScrollController.hasClients) return;
    final position = _dashboardScrollController.position;
    final selected = position.pixels <= position.minScrollExtent + 1;
    if (selected == _dashboardLogoutSelected || !mounted) return;
    setState(() => _dashboardLogoutSelected = selected);
  }

  Future<void> _requestDisconnect() async {
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: AppLocale.disconnectRaConfirm.getString(context),
      body: AppLocale.disconnectRaConfirmBody.getString(context),
      confirmLabel: AppLocale.logout.getString(context),
      icon: Symbols.logout_rounded,
    );
    if (!confirmed || !mounted) return;
    context.read<RetroAchievementsProvider>().disconnect(clearSavedUser: true);
    if (!mounted) return;
    setState(() {
      _selectedFieldIndex = 0;
      _dashboardLogoutSelected = true;
    });
    AppNotification.showNotification(
      context,
      AppLocale.disconnectedRA.getString(context),
      type: NotificationType.info,
    );
  }

  Future<void> _connectToRA() async {
    final raProvider = context.read<RetroAchievementsProvider>();
    if (raProvider.isLoading) return;
    final apiKey = _apiKeyController.text.trim();
    final success = await raProvider.connect(
      _usernameController.text,
      apiKey: apiKey,
    );
    if (!mounted) return;
    if (success) {
      AppNotification.showNotification(
        context,
        AppLocale.successConnectedRA.getString(context),
        type: NotificationType.success,
      );
    } else if (raProvider.error != null) {
      AppNotification.showNotification(
        context,
        raProvider.error!,
        type: NotificationType.error,
      );
    }
  }

  @override
  void dispose() {
    if (identical(_currentInstance, this)) {
      _currentInstance = null;
    }
    GamepadNavigationManager.popLayer('ra_content');
    _gamepadNav?.dispose();
    _usernameController.dispose();
    _apiKeyController.dispose();
    _usernameFocus.dispose();
    _apiKeyFocus.dispose();
    _dashboardScrollController.dispose();
    super.dispose();
  }

  static bool navigateUp({bool repeat = false}) =>
      _currentInstance?._handleNavigateUp(repeat) ?? true;

  static bool navigateDown({bool repeat = false}) =>
      _currentInstance?._handleNavigateDown(repeat) ?? true;

  bool _handleNavigateUp(bool repeat) {
    final raProvider = context.read<RetroAchievementsProvider>();
    if (!raProvider.isConnected) {
      if (repeat) return false;
      return _moveSelection(-1);
    }
    return _scrollDashboard(-160.r);
  }

  bool _handleNavigateDown(bool repeat) {
    final raProvider = context.read<RetroAchievementsProvider>();
    if (!raProvider.isConnected) {
      if (repeat) return false;
      return _moveSelection(1);
    }
    return _scrollDashboard(160.r);
  }

  bool _scrollDashboard(double delta) {
    if (!_dashboardScrollController.hasClients) return false;
    final position = _dashboardScrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 1) return false;
    _dashboardScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RetroAchievementsProvider>(
      builder: (context, raProvider, child) {
        return Responsive(
          handheldXS: _buildLandscapeLayout(context, raProvider),
          handheldSmall: _buildLandscapeLayout(context, raProvider),
          handheldMedium: _buildLandscapeLayout(context, raProvider),
          handheldLarge: _buildLandscapeLayout(context, raProvider),
          handheldXL: _buildLandscapeLayout(context, raProvider),
        );
      },
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 64.r), // Space for header (32.r + margin)
          // Contenido principal
          if (!raProvider.isConnected) ...[
            Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.r),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        constraints: BoxConstraints(maxWidth: 260.r),
                        child: _buildLandscapeConnectionForm(
                          context,
                          raProvider,
                        ),
                      ),
                      SizedBox(width: 16.r),
                      SizedBox(width: 300.r, child: _buildInfoBox(context)),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
            Expanded(
              child: RepaintBoundary(
                child: RADashboardHub(
                  scrollController: _dashboardScrollController,
                  logoutSelected: _dashboardLogoutSelected,
                  onDisconnectRequested: _requestDisconnect,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldHighlight({
    required int slot,
    required ThemeData theme,
    required Widget child,
  }) {
    if (!_isSelected(slot)) return child;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
            blurRadius: 6.r,
            spreadRadius: 1.r,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildLandscapeConnectionForm(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          width: 1.r,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header principal con logo y título
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocale.raLogin.getString(context),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    fontSize: 14.r,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 6.r),

          // Username field
          Container(
            constraints: BoxConstraints(maxWidth: 220.r),
            child: _buildFieldHighlight(
              slot: 0,
              theme: theme,
              child: SizedBox(
                height: 32.r,
                child: TextFormField(
                  controller: _usernameController,
                  focusNode: _usernameFocus,
                  decoration: InputDecoration(
                    labelText: AppLocale.username.getString(context),
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 10.r,
                    ),
                    floatingLabelStyle: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 10.r,
                      fontWeight: FontWeight.bold,
                    ),
                    hintText: AppLocale.enterUsername.getString(context),
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 10.r,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.05,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide(
                        color: _isSelected(0)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withValues(alpha: 0.1),
                        width: _isSelected(0) ? 2.r : 1.r,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.r,
                      ),
                    ),
                  ),
                  style: TextStyle(fontSize: 11.r),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _apiKeyFocus.requestFocus(),
                ),
              ),
            ),
          ),
          SizedBox(height: 6.r),

          // API key field
          Container(
            constraints: BoxConstraints(maxWidth: 220.r),
            child: _buildFieldHighlight(
              slot: 1,
              theme: theme,
              child: SizedBox(
                height: 32.r,
                child: TextFormField(
                  controller: _apiKeyController,
                  focusNode: _apiKeyFocus,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: AppLocale.raApiKey.getString(context),
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 10.r,
                    ),
                    floatingLabelStyle: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 10.r,
                      fontWeight: FontWeight.bold,
                    ),
                    hintText: AppLocale.raEnterApiKey.getString(context),
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 10.r,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.05,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide(
                        color: _isSelected(1)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withValues(alpha: 0.1),
                        width: _isSelected(1) ? 2.r : 1.r,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.r,
                      ),
                    ),
                  ),
                  style: TextStyle(fontSize: 11.r),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _connectToRA(),
                ),
              ),
            ),
          ),
          SizedBox(height: 6.r),

          // Connect button
          Container(
            constraints: BoxConstraints(maxWidth: 220.r),
            decoration: _isSelected(2)
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8.r),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                        blurRadius: 8.r,
                        spreadRadius: 2.r,
                      ),
                    ],
                  )
                : null,
            child: SizedBox(
              width: double.infinity,
              height: 32.r,
              child: ElevatedButton(
                onPressed: raProvider.isLoading ? null : _connectToRA,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  elevation: 0,
                ),
                child: raProvider.isLoading
                    ? SizedBox(
                        width: 16.r,
                        height: 16.r,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      )
                    : Text(
                        AppLocale.connect.getString(context),
                        style: TextStyle(
                          fontSize: 14.r,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          width: 1.r,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Symbols.emoji_events_rounded,
                color: theme.colorScheme.primary,
                size: 24.r,
              ),
              SizedBox(width: 12.r),
              Expanded(
                child: Text(
                  AppLocale.raWhatIs.getString(context),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    fontSize: 14.r,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.r),
          Text(
            AppLocale.raDescription.getString(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
              fontSize: 8.r,
            ),
            softWrap: true,
          ),
          SizedBox(height: 6.r),
          _buildInfoItem(
            context,
            Symbols.star_outline_rounded,
            AppLocale.raEarnPoints.getString(context),
          ),
          _buildInfoItem(
            context,
            Symbols.public_rounded,
            AppLocale.raGlobalLeaderboards.getString(context),
          ),
          _buildInfoItem(
            context,
            Symbols.history_rounded,
            AppLocale.raGameplayHistory.getString(context),
          ),
          SizedBox(height: 6.r),
          RichText(
            softWrap: true,
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 8.r,
              ),
              children: [
                TextSpan(text: AppLocale.raCreateAccountAt.getString(context)),
                TextSpan(
                  text: 'retroachievements.org',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () async {
                      final url = Uri.parse('https://retroachievements.org');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                ),
                TextSpan(text: AppLocale.raToStartEarning.getString(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 8.r),
      child: Row(
        children: [
          Icon(
            icon,
            size: 12.r,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
          SizedBox(width: 8.r),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 8.r,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

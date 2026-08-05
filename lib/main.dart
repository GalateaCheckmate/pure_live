import 'package:pure_live/common/index.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pure_live/common/global/initialized.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/routes/route_observer_controller.dart';
import 'package:pure_live/common/global/platform/desktop_manager.dart';

void main(List<String> args) async {
  await AppInitializer().initialize(args);

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('zh')],
      path: 'assets/translations',
      fallbackLocale: const Locale('zh'),
      assetLoader: const RootBundleAssetLoader(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with DesktopWindowMixin {
  @override
  void initState() {
    super.initState();
    DesktopManager.initializeListeners(this);
    GlobalPlayerService.instance.initialize(defaultEngine: PlayerEngine.mediaKit);
  }

  @override
  void dispose() {
    DesktopManager.disposeListeners();
    GlobalPlayerService.instance.playerManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return Obx(() {
          final themeColor = HexColor(SettingsService.to.theme.themeColorSwitch.v);
          final showSplashPage = SettingsService.to.app.showSplashPage.v;
          final currentFactor = SettingsService.to.font.textScaleFactor.v;

          ThemeData lightTheme;
          ThemeData darkTheme;

          if (SettingsService.to.theme.enableDynamicTheme.v && lightDynamic != null && darkDynamic != null) {
            lightTheme = MyTheme(colorScheme: lightDynamic.harmonized()).lightThemeData;
            darkTheme = MyTheme(colorScheme: darkDynamic.harmonized()).darkThemeData;
          } else {
            lightTheme = MyTheme(primaryColor: themeColor).lightThemeData;
            darkTheme = MyTheme(primaryColor: themeColor).darkThemeData;
          }

          return GetMaterialApp(
            title: i18n('app_name'),
            scrollBehavior: MyCustomScrollBehavior(),
            debugShowCheckedModeBanner: false,
            themeMode: AppConsts.themeModes[SettingsService.to.theme.themeModeName.v]!,
            theme: lightTheme.copyWith(
              appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
            ),
            darkTheme: darkTheme.copyWith(
              appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
            ),
            locale: context.locale,
            navigatorObservers: [FlutterSmartDialog.observer, BackButtonObserver()],
            builder: FlutterSmartDialog.init(
              builder: (context, child) {
                final resultWidget = DesktopManager.buildWithTitleBar(
                  child ?? const SizedBox.shrink(),
                );
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(currentFactor),
                  ),
                  child: resultWidget,
                );
              },
            ),
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            initialRoute: showSplashPage ? RoutePath.kSplash : RoutePath.kInitial,
            defaultTransition: Transition.native,
            routingCallback: (routing) {
              if (routing != null) {
                RouteObserverController.to.updateRoute(routing.current);
              }
            },
            getPages: AppPages.routes,
          );
        });
      },
    );
  }
}

import 'package:flutter/material.dart';

// ===== Auth screens =====
import 'features/auth/landing_page.dart';
import 'features/auth/welcome_page.dart';
import 'features/auth/login_page.dart' as lp;
import 'features/auth/register_page.dart' as rp;
import 'features/auth/email_verification_page.dart'; // Keep this
// import 'features/auth/phone_verification_page.dart'; // removed for now

// ===== Home + core pages =====
import 'features/home/home_shell.dart';
import 'features/home/pages/search_page.dart';
import 'features/home/pages/post_page.dart';
import 'features/home/pages/trips_page.dart' as trips_alias;
import 'features/home/pages/messages_page.dart';
import 'features/home/pages/help_page.dart';

// ===== Post flow (Need / Offer) =====
import 'features/home/pages/need_ride_page.dart';
import 'features/home/pages/offer_ride_page.dart';

// ===== Map Picker Integration =====
import 'features/home/pages/map/map_picker_page.dart';

// ===== Trips (results/details/booking) =====
import 'features/home/pages/search_results_page.dart';
import 'features/home/pages/trip_booking_page.dart';

// ===== Bookings & Driver Requests =====
import 'features/home/pages/my_bookings_page.dart';
import 'features/home/pages/driver_requests_page.dart';
import 'features/home/pages/booking_status_page.dart';
import 'features/home/pages/chat_screen.dart';
import 'features/home/pages/rate_trip_page.dart';
import 'features/home/pages/rate_riders_list_page.dart';

// ===== Driver Manage Trip =====
import 'features/home/pages/driver_manage_trip_page.dart';

// ===== Driver Profile =====
import 'features/home/pages/driver_profile_page.dart';
import 'features/home/pages/report_driver_page.dart'; // ✅ NEW

// ===== Payment & Status =====
import 'features/home/pages/final_payment_page.dart';
// ===== Payment Gateway =====
import 'features/payments/payment_gateway_page.dart';
// Payment success page
import 'features/payments/payment_success_page.dart';

// ===== Onboarding =====
import 'features/onboarding/pages/onboard_intro_page.dart';
import 'features/onboarding/pages/onboard_community_page.dart';
import 'features/onboarding/pages/onboard_payments_page.dart';
import 'features/onboarding/pages/onboard_early_page.dart';
import 'features/onboarding/pages/onboard_agree_page.dart';

// ===== Profile Setup =====
import 'features/onboarding/pages/profile_setup_intro_page.dart';
import 'features/onboarding/pages/profile_age_page.dart';
import 'features/onboarding/pages/profile_gender_page.dart';
import 'features/onboarding/pages/profile_use_page.dart'
    as profile_use; // 🔹 alias
import 'features/onboarding/pages/profile_phone_page.dart'
    as profile_phone; // 🔹 alias
import 'features/onboarding/pages/profile_picture_page.dart';
import 'features/onboarding/pages/profile_review_page.dart';
import 'features/onboarding/pages/profile_notifications_page.dart';
import 'features/onboarding/pages/profile_completed_page.dart';
import 'features/onboarding/pages/driver_license_page.dart';
// 🔹 must export both DriverLicensePage and ProfileSetupArgs from this file

// ===== Account / Profile pages =====
import 'features/home/pages/profile_page.dart';
import 'features/profile/account_page.dart';
import 'features/profile/view_profile_page.dart';
import 'features/profile/profile_settings_page.dart';
import 'features/profile/notifications_page.dart';
import 'features/profile/personal_details_page.dart';
import 'features/profile/preferences_page.dart';
import 'features/profile/vehicles_page.dart';
import 'features/profile/email_address_page.dart';
import 'features/profile/change_password_page.dart';
import 'features/profile/language_page.dart';
import 'features/profile/my_reviews_page.dart'; // ✅ NEW

// ===== Wallet =====
import 'features/wallet/wallet_page.dart';
import 'features/wallet/add_money_page.dart';
import 'features/wallet/withdraw_page.dart';
import 'features/wallet/bank_setup_page.dart';

// ===== Info / Social / Support =====
import 'features/profile/refer_friend_page.dart';
import 'features/profile/social_hub_page.dart';
import 'features/profile/about_page.dart';
import 'features/profile/terms_page.dart';
import 'features/profile/close_account_page.dart';
import 'features/profile/support_page.dart';

/// Route name constants
class Routes {
  // Auth / shell
  static const String landing = '/'; // 👈 used by BannedUserGate
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';

  // Home tabs (named direct access)
  static const String homeSearch = '/home/search';
  static const String homeTrips = '/home/trips';
  static const String homePost = '/home/post';
  static const String homeMessages = '/home/messages';
  static const String homeHelp = '/home/help';
  static const String homeProfile = '/home/profile';

  // Verify
  static const String emailVerify = '/auth/email_verify';

  // Post flow forms
  static const String postNeed = '/post/need';
  static const String postOffer = '/post/offer';

  // 🔹 Legacy offer-ride gate route
  static const String offerRideGate = '/offer/gate';

  // Map Picker
  static const String mapPicker = '/map/picker';

  // Search / Trips
  static const String searchResults = '/search/results';
  static const String tripBooking = '/trip/booking';
  static const String tripPaymentFinal = '/trip/payment/final';
  static const String rateTrip = '/trip/rate';
  static const String rateRidersList = '/trip/rate-riders';

  // Booking Status & Requests
  static const String bookingStatus = '/booking/status';
  static const String driverRequests = '/driver/requests';

  // Bookings & Requests
  static const String myBookings = '/my_bookings';

  // Chat
  static const String chatScreen = '/chat';

  // Driver Manage Trip
  static const String driverManageTrip = '/driver/manageTrip';

  // Account
  static const String account = '/account';

  // Profile settings
  static const String viewProfile = '/view_profile';
  static const String viewDriverProfile = '/view_driver_profile';
  static const String reportDriver = '/report_driver'; // ✅ NEW
  static const String profileSettings = '/profile_settings';
  static const String notifications = '/notifications';
  static const String personalDetails = '/personal_details';
  static const String preferences = '/preferences';
  static const String vehicles = '/vehicles';
  static const String emailAddress = '/email_address';
  static const String changePassword = '/change_password';
  static const String language = '/language';
  static const String myReviews = '/my_reviews'; // ✅ NEW

  // Onboarding/Setup
  static const String onboardingStart = '/onboarding/start';
  static const String onboardCommunity = '/onboarding/community';
  static const String onboardPayments = '/onboarding/payments';
  static const String onboardEarly = '/onboarding/early';
  static const String onboardAgree = '/onboarding/agree';

  // Profile setup
  static const String profileSetupIntro = '/profile/setup/intro';
  static const String profileSetupAge = '/profile/setup/age';
  static const String profileSetupGender = '/profile/setup/gender';
  static const String profileSetupUse = '/profile/setup/use';
  static const String profileSetupPhone =
      '/profile/setup/phone'; // ✅ phone step
  static const String phoneVerification =
      profileSetupPhone; // ✅ legacy alias
  static const String profileSetupPicture = '/profile/setup/picture';
  static const String profileSetupReview = '/profile/setup/review';
  static const String profileSetupNotifications =
      '/profile/setup/notifications';
  static const String profileSetupCompleted = '/profile/setup/completed';

  // Driver licence verification step
  static const String driverLicense = '/profile/setup/driver_license';

  // Wallet
  static const String wallet = '/wallet';
  static const String walletAdd = '/wallet/add';
  static const String walletWithdraw = '/wallet/withdraw';
  static const String walletBank = '/wallet/bank';

  // Info / Social / Support
  static const String referFriend = '/refer_friend';
  static const String socialHub = '/social_hub';
  static const String support = '/support_page';
  static const String about = '/about';
  static const String terms = '/terms';
  static const String closeAccount = '/close_account';

  // Payment Gateway
  static const String paymentGateway = '/payments/checkout';

  // Payment success route (for Stripe redirect)
  static const String paymentSuccess = '/payments/success';

  // Dev-only direct checkout route
  static const String devCheckout = '/dev/checkout';
}

class AppRouter {
  // ✅ Not actually used because you use `home:` in MaterialApp,
  // but fine to keep for reference.
  static const String initialRoute = Routes.home;

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      // ===== Auth =====
      case Routes.landing:
        return _page(const LandingPage(), settings);
      case Routes.welcome:
        return _page(const WelcomePage(), settings);
      case Routes.login:
        return _page(const lp.LoginPage(), settings);
      case Routes.register:
        return _page(const rp.RegisterPage(), settings);

      // Email verification
      case Routes.emailVerify:
        return _page(const EmailVerificationPage(), settings);

      // ===== Onboarding =====
      case Routes.onboardingStart:
        return _page(const OnboardIntroPage(), settings);
      case Routes.onboardCommunity:
        return _page(const OnboardCommunityPage(), settings);
      case Routes.onboardPayments:
        return _page(const OnboardPaymentsPage(), settings);
      case Routes.onboardEarly:
        return _page(const OnboardEarlyPage(), settings);
      case Routes.onboardAgree:
        return _page(const OnboardAgreePage(), settings);

      // ===== Profile setup =====
      case Routes.profileSetupIntro:
        return _page(const ProfileSetupIntroPage(), settings);
      case Routes.profileSetupAge:
        return _page(const ProfileAgePage(), settings);
      case Routes.profileSetupGender:
        return _page(const ProfileGenderPage(), settings);

      // usage (driver/passenger)
      case Routes.profileSetupUse:
        return _page(const profile_use.ProfileUsePage(), settings);

      // phone step (both driver + passenger go here in flow)
      case Routes.profileSetupPhone:
        return _page(const profile_phone.ProfilePhonePage(), settings);

      // Driver licence route (with optional args)
      case Routes.driverLicense:
        {
          final args = settings.arguments;
          ProfileSetupArgs? profileArgs;
          if (args is ProfileSetupArgs) {
            profileArgs = args;
          }
          return _page(
            DriverLicensePage(initialArgs: profileArgs),
            settings,
          );
        }

      case Routes.profileSetupPicture:
        return _page(const ProfilePicturePage(), settings);
      case Routes.profileSetupReview:
        return _page(const ProfileReviewPage(), settings);
      case Routes.profileSetupNotifications:
        return _page(const ProfileNotificationsPage(), settings);
      case Routes.profileSetupCompleted:
        return _page(const ProfileCompletedPage(), settings);

      // ===== Home shell & tabs =====
      case Routes.home:
        {
          int initialIndex = 0;
          final args = settings.arguments;
          String? tab;
          if (args is Map && args['tab'] is String) {
            tab = args['tab'] as String?;
          } else if (args is String) {
            tab = args;
          }

          switch (tab) {
            case 'search':
              initialIndex = 0;
              break;
            case 'post':
              initialIndex = 1;
              break;
            case 'trips':
              initialIndex = 2;
              break;
            case 'messages':
              initialIndex = 3;
              break;
            case 'help':
              initialIndex = 4;
              break;
            default:
              initialIndex = 0;
          }

          return _page(HomeShell(initialIndex: initialIndex), settings);
        }

      // Direct access to tabs/pages
      case Routes.homeSearch:
        return _page(const SearchPage(), settings);
      case Routes.homeTrips:
        return _page(const trips_alias.TripsPage(), settings);
      case Routes.homePost:
        return _page(const PostPage(), settings);
      case Routes.homeMessages:
        return _page(const MessagesPage(), settings);
      case Routes.homeHelp:
        return _page(const HelpPage(), settings);
      case Routes.homeProfile:
        return _page(const ProfilePage(), settings);

      // Map Picker
      case Routes.mapPicker:
        {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          final initialQuery = args['initialQuery'] as String? ?? '';
          return _page(MapPickerPage(initialQuery: initialQuery), settings);
        }

      // ===== Post forms =====
      case Routes.postNeed:
        {
          final args = settings.arguments as Map<String, dynamic>?;
          final requestIdToEdit = args?['requestIdToEdit'] as String?;
          return _page(
            NeedRidePage(requestIdToEdit: requestIdToEdit),
            settings,
          );
        }

      // Legacy offer-ride gate route: now goes directly to OfferRidePage.
      // (Popup gating is handled by the caller, not this route.)
      case Routes.offerRideGate:
        return _page(
          OfferRidePage(
            tripIdToEdit: settings.arguments as String?,
          ),
          settings,
        );

      // ===== Search / Trips =====
      case Routes.searchResults:
        {
          final a = settings.arguments;
          String from = '';
          String to = '';
          DateTime? date;
          int seats = 1;

          if (a is Map) {
            from = (a['from'] ?? '') as String;
            to = (a['to'] ?? '') as String;

            final rawDate = a['date'];
            if (rawDate is DateTime) {
              date = rawDate;
            } else if (rawDate is String && rawDate.isNotEmpty) {
              date = DateTime.tryParse(rawDate);
            }

            final rawSeats = a['seats'];
            if (rawSeats is int) seats = rawSeats;
          }

          return _page(
            SearchResultsPage(from: from, to: to, date: date, seats: seats),
            settings,
          );
        }

      // ===== Payment final =====
      case Routes.tripPaymentFinal:
        {
          final a = settings.arguments as Map<String, dynamic>? ?? {};
          return _page(
            FinalPaymentPage(
              tripId: (a['tripId'] ?? '').toString(),
              from: (a['from'] ?? '—').toString(),
              to: (a['to'] ?? '—').toString(),
              dateString: (a['dateString'] ?? '—').toString(),
              timeString: (a['timeString'] ?? '—').toString(),
              price: (a['price'] is num)
                  ? (a['price'] as num).toDouble()
                  : 0.0,
              availableSeats: (a['availableSeats'] is int)
                  ? (a['availableSeats'] as int)
                  : 1,
              driverName: (a['driverName'] is String)
                  ? (a['driverName'] as String)
                  : '—',
              driverId: (a['driverId'] ?? '').toString(),
              initialSeats: (a['initialSeats'] is int)
                  ? (a['initialSeats'] as int)
                  : 1,
              initialPaymentFull: (a['initialPaymentFull'] is bool)
                  ? (a['initialPaymentFull'] as bool)
                  : true,
              premiumSeatSelected: (a['premiumSeatSelected'] is bool)
                  ? (a['premiumSeatSelected'] as bool)
                  : false,
              premiumExtra: (a['premiumExtra'] is num)
                  ? (a['premiumExtra'] as num).toDouble()
                  : 0.0,
              extraLuggageCount: (a['extraLuggageCount'] is int)
                  ? (a['extraLuggageCount'] as int)
                  : 0,
              extraLuggagePrice: (a['extraLuggagePrice'] is num)
                  ? (a['extraLuggagePrice'] as num).toDouble()
                  : 0.0,
              // NEW: currency code from arguments, default INR
              currencyCode: (a['currencyCode'] ?? 'INR').toString(),
            ),
            settings,
          );
        }

      // ===== Payment Gateway =====
      case Routes.paymentGateway:
        {
          final a = settings.arguments as Map<String, dynamic>? ?? {};
          return _page(
            PaymentGatewayPage.fromArgs(a),
            settings,
          );
        }

      // Dev-only direct checkout
      case Routes.devCheckout:
        return _page(
          const PaymentGatewayPage(
            amount: 12.50,
            currency: 'INR', // use INR for dev too
            tripTitle: 'Test ride: Niagara → Hamilton',
            subtitle: '1 seat • Today',
          ),
          settings,
        );

      // Payment success
      case Routes.paymentSuccess:
        return _page(const PaymentSuccessPage(), settings);

      // ===== Ratings =====
      case Routes.rateTrip:
        {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return _page(
            RateTripPage(
              bookingId: (args['bookingId'] ?? '') as String,
              tripId: (args['tripId'] ?? '') as String,
              recipientId: (args['recipientId'] ?? '') as String,
              recipientName: (args['recipientName'] ?? 'User') as String,
              role: (args['role'] ?? 'rider') as String,
            ),
            settings,
          );
        }

      case Routes.rateRidersList:
        {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          final tripId = (args['tripId'] ?? '') as String;
          return _page(
            RateRidersListPage(tripId: tripId),
            settings,
          );
        }

      // ===== Booking status =====
      case Routes.bookingStatus:
        {
          final a = settings.arguments as Map<String, dynamic>? ?? {};
          return _page(
            BookingStatusPage(
              bookingId: (a['bookingId'] ?? '').toString(),
              tripId: (a['tripId'] ?? '').toString(),
              from: (a['from'] ?? '—').toString(),
              to: (a['to'] ?? '—').toString(),
              dateString: (a['dateString'] ?? '—').toString(),
              timeString: (a['timeString'] ?? '—').toString(),
              driverName: (a['driverName'] ?? '—').toString(),
            ),
            settings,
          );
        }

      // ===== Driver Requests / Manage =====
      case Routes.driverRequests:
        return _page(const DriverRequestsPage(), settings);

      case Routes.driverManageTrip:
        {
          final a = settings.arguments as Map?;
          final tripId = (a?['tripId'] ?? '').toString();
          if (tripId.isEmpty) {
            return _page(
              const _RouteProblemPage(
                message: 'Missing "tripId" for /driver/manageTrip',
              ),
              settings,
            );
          }
          return _page(DriverManageTripPage(tripId: tripId), settings);
        }

      // ===== Trip Booking =====
      case Routes.tripBooking:
        {
          final a = settings.arguments;
          if (a is Map) {
            return _page(TripBookingPage.fromArgs(a), settings);
          }
          return _page(
            const TripBookingPage(
              tripId: '',
              from: '—',
              to: '—',
              dateString: '—',
              timeString: '—',
              price: 0,
              availableSeats: 1,
              driverName: '—',
              driverId: '',
            ),
            settings,
          );
        }

      // ===== Chat =====
      case Routes.chatScreen:
        {
          final args = settings.arguments as Map<String, dynamic>?;
          final chatId = args?['chatId'] as String?;
          final recipientId = args?['recipientId'] as String? ?? '';
          final segmentFrom = args?['segmentFrom'] as String?;
          final segmentTo = args?['segmentTo'] as String?;
          final tripId = args?['tripId'] as String?;
          final requestId = args?['requestId'] as String?;
          return _page(
            ChatScreen(
              chatId: chatId,
              recipientId: recipientId,
              segmentFrom: segmentFrom,
              segmentTo: segmentTo,
              tripId: tripId,
              requestId: requestId,
            ),
            settings,
          );
        }

      // ===== Bookings =====
      case Routes.myBookings:
        return _page(const MyBookingsPage(), settings);

      // ===== Account & settings =====
      case Routes.account:
        return _page(const AccountPage(), settings);

      case Routes.viewProfile:
        return _page(const ViewProfilePage(), settings);

      case Routes.viewDriverProfile:
        {
          final args = settings.arguments as Map<String, dynamic>?;
          final driverId = args?['driverId'] as String? ?? '';
          final driverName = args?['driverName'] as String?;
          final vehicleInfo = args?['vehicleInfo'] as String?;
          if (driverId.isEmpty) {
            return _page(
              const _RouteProblemPage(
                message: 'Missing "driverId" for driver profile',
              ),
              settings,
            );
          }
          return _page(
            DriverProfilePage(
              driverId: driverId,
              driverName: driverName,
              vehicleInfo: vehicleInfo,
            ),
            settings,
          );
        }

      // ✅ NEW: Report Driver route
      case Routes.reportDriver:
        {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          final driverId = (args['driverId'] ?? '') as String;
          final driverName =
              (args['driverName'] as String?) ?? 'Driver';
          final tripId = args['tripId'] as String?;

          return _page(
            ReportDriverPage(
              driverId: driverId,
              driverName: driverName,
              tripId: tripId,
            ),
            settings,
          );
        }

      case Routes.profileSettings:
        return _page(const ProfileSettingsPage(), settings);

      case Routes.myReviews:
        return _page(const MyReviewsPage(), settings); // ✅ NEW

      case Routes.notifications:
        return _page(NotificationsPage(), settings);

      case Routes.personalDetails:
        return _page(const PersonalDetailsPage(), settings);
      case Routes.preferences:
        return _page(const PreferencesPage(), settings);
      case Routes.vehicles:
        return _page(const VehiclesPage(), settings);
      case Routes.emailAddress:
        return _page(const EmailAddressPage(), settings);
      case Routes.changePassword:
        return _page(const ChangePasswordPage(), settings);
      case Routes.language:
        return _page(const LanguagePage(), settings);

      // ===== Wallet =====
      case Routes.wallet:
        return _page(const WalletPage(), settings);
      case Routes.walletAdd:
        return _page(const AddMoneyPage(), settings);
      case Routes.walletWithdraw:
        return _page(const WithdrawPage(), settings);
      case Routes.walletBank:
        return _page(const BankSetupPage(), settings);

      // ===== Info / Social / Support =====
      case Routes.referFriend:
        return _page(const ReferFriendPage(), settings);
      case Routes.socialHub:
        return _page(const SocialHubPage(), settings);
      case Routes.support:
        return _page(const SupportPage(), settings);
      case Routes.about:
        return _page(const AboutPage(), settings);
      case Routes.terms:
        return _page(const TermsPage(), settings);
      case Routes.closeAccount:
        return _page(const CloseAccountPage(), settings);

      // ===== Default =====
      default:
        // ✅ Fallback to Home instead of Landing
        return _page(HomeShell(initialIndex: 0), settings);
    }
  }

  static MaterialPageRoute _page(Widget child, RouteSettings settings) {
    return MaterialPageRoute(builder: (_) => child, settings: settings);
  }
}

/// Simple message page for required-arg problems
class _RouteProblemPage extends StatelessWidget {
  final String message;
  const _RouteProblemPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Route Problem')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
}

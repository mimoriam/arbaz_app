import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/utils/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isLoading = false;

  Future<void> _handlePurchase(String plan) async {
    setState(() => _isLoading = true);
    
    // Mock purchase delay
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Determine if this is a paid plan
        final isPro = plan == 'plus' || plan == 'premium';
        
        // Update server-side verification status with plan type
        // In a real app, this would be a cloud function triggered by store receipt
        await context.read<FirestoreService>().setProStatus(
          user.uid, 
          isPro, 
          subscriptionPlan: plan,
        );
        
        if (mounted) {
          final planName = plan == 'plus' ? 'Plus' : (plan == 'premium' ? 'Premium' : 'Free');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isPro ? 'Welcome to $planName! Subscription active.' : 'Switched to Free plan.',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.successGreen,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Plan change failed. Please try again.', style: GoogleFonts.inter()),
              backgroundColor: AppColors.dangerRed,
            ),
          );
        }
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppColors.backgroundDark : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: isDarkMode ? Colors.white : Colors.black87,
            size: 28,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Choose Your Plan',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: isDarkMode ? Colors.white : AppColors.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Unlock all features with monthly billing',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            
            // Plans
            _buildPlanCard(
              title: 'Plus',
              price: '\$6.99',
              period: '/month',
              features: [
                'Everything in Free',
                'Unlimited contacts',
                'All 10 brain games',
                'Cognitive tracking',
                'Emergency info vault',
                'Doctor reports',
              ],
              isPopular: true,
              isDarkMode: isDarkMode,
              onTap: () => _handlePurchase('plus'),
            ),
            
            const SizedBox(height: 12),
            
            _buildPlanCard(
              title: 'Premium',
              price: '\$12.99',
              period: '/month',
              features: [
                'Everything in Plus',
                '24/7 Dispatcher Service',
                'Emergency Button',
                'Priority Support',
                'Family Plan (3 seniors)',
              ],
              isDarkMode: isDarkMode,
              onTap: () => _handlePurchase('premium'),
            ),
            
             const SizedBox(height: 12),

             _buildPlanCard(
              title: 'Free',
              price: '\$0',
              period: '/month',
              features: [
                '1 daily check-in',
                '2 emergency contacts',
                'Basic reminders',
                '1 brain game per day',
                '7-day history',
              ],
              isDarkMode: isDarkMode,
              isFree: true,
              onTap: () => _handlePurchase('free'),
            ),

            const SizedBox(height: 20),
              
            const SizedBox(height: 24),
            
            Text(
              'Cancel anytime. No commitment.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
  
  
  Widget _buildPlanCard({
    required String title,
    required String price,
    required String period,
    required List<String> features,
    bool isPopular = false,
    bool isFree = false,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    return Stack(
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isPopular 
                  ? AppColors.primaryTeal 
                  : (isDarkMode ? AppColors.borderDark : AppColors.borderLight),
              width: isPopular ? 2 : 1,
            ),
            boxShadow: isPopular
                ? [
                    BoxShadow(
                      color: AppColors.primaryTeal.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    )
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPopular) const SizedBox(height: 8),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDarkMode ? Colors.white : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    price,
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: isPopular ? AppColors.primaryTeal : (isDarkMode ? Colors.white : AppColors.textPrimary),
                    ),
                  ),
                  Text(
                    period,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ...features.map((feature) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.check,
                      size: 20,
                      color: isPopular ? AppColors.primaryTeal : AppColors.successGreen,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        feature,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFree 
                        ? Colors.transparent 
                        : (isPopular ? AppColors.primaryOrange : Colors.white),
                    foregroundColor: isFree 
                        ? AppColors.primaryTeal 
                        : (isPopular ? Colors.white : AppColors.primaryTeal),
                    elevation: isPopular ? 4 : 0,
                    side: isFree || !isPopular 
                        ? const BorderSide(color: AppColors.primaryTeal) 
                        : null,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Select Plan',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        if (isPopular)
          Positioned(
            top: -12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryTeal,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'MOST POPULAR',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

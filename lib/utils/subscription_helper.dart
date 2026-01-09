/// Centralized helper for subscription plan feature gating.
/// 
/// Plan tiers:
/// - Free: Limited features (1 check-in schedule, 2 family members, 1 game/day, 7-day history)
/// - Plus: Everything in Free + unlimited contacts, all games, emergency vault
/// - Premium: Everything in Plus + SOS Emergency Button
class SubscriptionHelper {
  // Plan constants
  static const String planFree = 'free';
  static const String planPlus = 'plus';
  static const String planPremium = 'premium';
  
  // Free plan limits
  static const int freeMaxCheckInSchedules = 1;
  static const int freeMaxFamilyMembers = 2;
  static const int freeMaxGamesPerDay = 1;
  static const int freeHistoryDays = 7;
  
  /// Check if the plan is the free tier (or null/unset)
  static bool isFreePlan(String? plan) {
    return plan == null || plan.isEmpty || plan == planFree;
  }
  
  /// Check if the plan is Plus tier
  static bool isPlusPlan(String? plan) {
    return plan == planPlus;
  }
  
  /// Check if the plan is Premium tier
  static bool isPremiumPlan(String? plan) {
    return plan == planPremium;
  }
  
  /// Check if the plan is any paid tier (Plus or Premium)
  static bool isPaidPlan(String? plan) {
    return isPlusPlan(plan) || isPremiumPlan(plan);
  }
  
  /// Check if user can add another check-in schedule.
  /// Free: max 1, Plus/Premium: unlimited
  static bool canAddCheckInSchedule(String? plan, int currentCount) {
    if (isPaidPlan(plan)) return true;
    return currentCount < freeMaxCheckInSchedules;
  }
  
  /// Check if user can add another family member.
  /// Free: max 2, Plus/Premium: unlimited
  static bool canAddFamilyMember(String? plan, int currentCount) {
    if (isPaidPlan(plan)) return true;
    return currentCount < freeMaxFamilyMembers;
  }
  
  /// Check if user can play another game today.
  /// Free: max 1/day, Plus/Premium: unlimited
  static bool canPlayGame(String? plan, int gamesPlayedToday) {
    if (isPaidPlan(plan)) return true;
    return gamesPlayedToday < freeMaxGamesPerDay;
  }
  
  /// Check if user can view history beyond 7 days.
  /// Free: 7 days only, Plus/Premium: unlimited
  static bool canViewHistoryBeyond7Days(String? plan) {
    return isPaidPlan(plan);
  }
  
  /// Check if user can access the Emergency Vault.
  /// Free: no, Plus/Premium: yes
  static bool canAccessEmergencyVault(String? plan) {
    return isPaidPlan(plan);
  }
  
  /// Check if user can use the SOS Emergency Button.
  /// Premium only
  static bool canUseSosButton(String? plan) {
    return isPremiumPlan(plan);
  }
  
  /// Check if a date is within the free plan's history limit (7 days).
  static bool isDateWithinFreeHistoryLimit(DateTime date) {
    final now = DateTime.now();
    final sevenDaysAgo = DateTime(now.year, now.month, now.day - freeHistoryDays);
    // Compare dates (not times)
    final dateOnly = DateTime(date.year, date.month, date.day);
    return !dateOnly.isBefore(sevenDaysAgo);
  }
  
  /// Get display text for current plan
  static String getPlanDisplayName(String? plan) {
    switch (plan) {
      case planPlus:
        return 'Plus';
      case planPremium:
        return 'Premium';
      default:
        return 'Free';
    }
  }
  
  /// Get the required plan for a feature (for upgrade prompts)
  static String getRequiredPlanForFeature(String feature) {
    switch (feature) {
      case 'sos_button':
        return planPremium;
      case 'unlimited_schedules':
      case 'unlimited_contacts':
      case 'unlimited_games':
      case 'full_history':
      case 'emergency_vault':
        return planPlus;
      default:
        return planPlus;
    }
  }
}

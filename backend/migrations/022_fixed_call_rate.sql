-- Fixed call pricing: the caller pays Rs 1.25 per minute (125 paise), the host earns Rs 1.00 (100 paise), Talkory keeps Rs 0.25.
UPDATE partner_profiles SET rate_per_min = 125, payout_share = 0.8;

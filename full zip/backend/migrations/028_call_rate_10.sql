-- Call price: the caller pays Rs 10 per minute (1000 paise), the host earns Rs 6 (600 paise), Talkory keeps Rs 4. 10 minutes = 100 coins.
UPDATE partner_profiles SET rate_per_min = 1000, payout_share = 0.6;

// Coins the user app shows. Wallets, prices and the ledger stay in rupees/paise on the server;
// coins are only how amounts are shown to users: COINS_PER_RUPEE coins = Rs 1 (3 by default).
// Changing it re-prices nothing: Rs 100 is still Rs 100, it just shows as 300 coins.
const COINS_PER_RUPEE = Number(process.env.COINS_PER_RUPEE || 3);

/// Rupees -> coins shown to the user (rounded to 1 decimal).
const coins = (rupees) => Math.round(Number(rupees) * COINS_PER_RUPEE * 10) / 10;

module.exports = { COINS_PER_RUPEE, coins };

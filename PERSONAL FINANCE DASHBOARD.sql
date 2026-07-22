/*
===============================================================================
PERSONAL FINANCE DASHBOARD
===============================================================================

PURPOSE
-------

This script creates reporting views for the Personal Finance Management System.

The dashboard is designed around four questions:

    1. WHERE DID MY MONEY GO?
    2. WHAT CAN I REDUCE?
    3. HOW MUCH DEBT CAN I PAY?
    4. HOW MUCH CAN I SAVE?


MAIN DASHBOARD
--------------

The application should be able to show:

    Total Income
    Total Expenses
    Net Cashflow
    Total Account Balance
    Total Debt
    Total Loan Closing Amount
    Monthly EMI
    Debt-to-Income Ratio
    Savings Progress
    Budget Alerts
    Top Spending Categories


IMPORTANT
---------

This file assumes the following tables already exist:

    accounts
    categories
    transactions
    budgets
    loans
    loan_payments
    savings_goals
    savings_contributions


===============================================================================
*/


/*
===============================================================================
1. MONTHLY FINANCIAL SUMMARY
===============================================================================

PURPOSE
-------

Shows the complete financial performance for every month.

Example:

    July 2026

    Income          NPR 45,000
    Expenses        NPR 30,000
    Net Cashflow    NPR 15,000


FORMULA
-------

Net Cashflow = Total Income - Total Expenses


This answers:

    "How much money did I actually keep this month?"
===============================================================================
*/

CREATE OR REPLACE VIEW v_monthly_financial_summary AS

SELECT

    DATE_TRUNC(
        'month',
        transaction_date
    )::DATE AS month,

    COALESCE(
        SUM(
            CASE
                WHEN transaction_type = 'INCOME'
                THEN amount
                ELSE 0
            END
        ),
        0
    ) AS total_income,

    COALESCE(
        SUM(
            CASE
                WHEN transaction_type = 'EXPENSE'
                THEN amount
                ELSE 0
            END
        ),
        0
    ) AS total_expenses,

    COALESCE(
        SUM(
            CASE
                WHEN transaction_type = 'INCOME'
                THEN amount

                WHEN transaction_type = 'EXPENSE'
                THEN -amount

                ELSE 0
            END
        ),
        0
    ) AS net_cashflow,

    CASE

        WHEN SUM(
            CASE
                WHEN transaction_type = 'INCOME'
                THEN amount
                ELSE 0
            END
        ) = 0

        THEN 0

        ELSE ROUND(

            (

                SUM(
                    CASE
                        WHEN transaction_type = 'INCOME'
                        THEN amount

                        WHEN transaction_type = 'EXPENSE'
                        THEN -amount

                        ELSE 0
                    END
                )

                /

                SUM(
                    CASE
                        WHEN transaction_type = 'INCOME'
                        THEN amount
                        ELSE 0
                    END
                )

            ) * 100,

            2

        )

    END AS savings_rate_percentage

FROM transactions

GROUP BY

    DATE_TRUNC(
        'month',
        transaction_date
    )::DATE

ORDER BY

    month;


/*
===============================================================================
2. CURRENT ACCOUNT BALANCE
===============================================================================

PURPOSE
-------

Shows how much money you currently have across all accounts.

Example:

    Laxmi Sunrise Bank     NPR 50,000
    Kumari Bank            NPR 20,000
    eSewa                  NPR  2,000
    Cash                   NPR  1,000

    Total Assets           NPR 73,000
===============================================================================
*/

CREATE OR REPLACE VIEW v_total_account_balance AS

SELECT

    COALESCE(
        SUM(calculated_balance),
        0
    ) AS total_account_balance

FROM v_account_balances

WHERE calculated_balance >= 0;


/*
===============================================================================
3. TOTAL DEBT DASHBOARD
===============================================================================

PURPOSE
-------

Shows your complete debt situation.

Example:

    Active Loans             2

    Outstanding Principal    NPR 91,528

    Required To Close        NPR 143,590

    Monthly EMI              NPR 14,206
===============================================================================
*/

CREATE OR REPLACE VIEW v_debt_dashboard AS

SELECT

    COUNT(*) AS active_loan_count,

    COALESCE(
        SUM(outstanding_principal),
        0
    ) AS total_outstanding_principal,

    COALESCE(
        SUM(required_to_close),
        0
    ) AS total_required_to_close,

    COALESCE(
        SUM(emi_amount),
        0
    ) AS total_monthly_emi

FROM loans

WHERE status = 'ACTIVE';


/*
===============================================================================
4. DEBT-TO-INCOME RATIO
===============================================================================

PURPOSE
-------

Measures how much of your income is committed to loan payments.

FORMULA:

    Monthly EMI
    -----------
    Monthly Income

    x 100


Example:

    Monthly Income = NPR 45,000

    Monthly EMI    = NPR 14,206

    DTI = 31.57%


INTERPRETATION:

    < 20%    Healthy
    20-35%   Manageable
    35-50%   Risky
    > 50%    High Risk


NOTE:

This is a personal financial indicator, not a formal bank lending calculation.
===============================================================================
*/

CREATE OR REPLACE VIEW v_debt_to_income AS

WITH latest_month AS (

    SELECT

        DATE_TRUNC(
            'month',
            CURRENT_DATE
        )::DATE AS month

),

income AS (

    SELECT

        COALESCE(
            SUM(amount),
            0
        ) AS monthly_income

    FROM transactions

    WHERE transaction_type = 'INCOME'

    AND transaction_date >= (
        SELECT month
        FROM latest_month
    )

    AND transaction_date < (
        SELECT month + INTERVAL '1 month'
        FROM latest_month
    )

),

debt AS (

    SELECT

        COALESCE(
            SUM(emi_amount),
            0
        ) AS monthly_emi

    FROM loans

    WHERE status = 'ACTIVE'

)

SELECT

    income.monthly_income,

    debt.monthly_emi,

    CASE

        WHEN income.monthly_income = 0

            THEN 0

        ELSE ROUND(

            (
                debt.monthly_emi
                /
                income.monthly_income
            ) * 100,

            2

        )

    END AS debt_to_income_percentage,

    CASE

        WHEN income.monthly_income = 0
            THEN 'NO_INCOME_DATA'

        WHEN (
            debt.monthly_emi
            /
            income.monthly_income
        ) * 100 < 20

            THEN 'HEALTHY'

        WHEN (
            debt.monthly_emi
            /
            income.monthly_income
        ) * 100 < 35

            THEN 'MANAGEABLE'

        WHEN (
            debt.monthly_emi
            /
            income.monthly_income
        ) * 100 < 50

            THEN 'RISKY'

        ELSE 'HIGH_RISK'

    END AS debt_status

FROM income

CROSS JOIN debt;


/*
===============================================================================
5. CURRENT MONTH CASHFLOW
===============================================================================

PURPOSE
-------

Provides the main numbers for the dashboard.

Example:

    Current Month:

    Income       NPR 45,000
    Expenses     NPR 30,000
    Savings      NPR 15,000


This is the main "How am I doing this month?" metric.
===============================================================================
*/

CREATE OR REPLACE VIEW v_current_month_cashflow AS

SELECT

    COALESCE(

        SUM(

            CASE
                WHEN transaction_type = 'INCOME'
                THEN amount
                ELSE 0
            END

        ),

        0

    ) AS total_income,

    COALESCE(

        SUM(

            CASE
                WHEN transaction_type = 'EXPENSE'
                THEN amount
                ELSE 0
            END

        ),

        0

    ) AS total_expenses,

    COALESCE(

        SUM(

            CASE

                WHEN transaction_type = 'INCOME'
                    THEN amount

                WHEN transaction_type = 'EXPENSE'
                    THEN -amount

                ELSE 0

            END

        ),

        0

    ) AS available_cashflow

FROM transactions

WHERE transaction_date >= DATE_TRUNC(
    'month',
    CURRENT_DATE
)

AND transaction_date < DATE_TRUNC(
    'month',
    CURRENT_DATE
) + INTERVAL '1 month';


/*
===============================================================================
6. TOP SPENDING CATEGORIES
===============================================================================

PURPOSE
-------

Shows where your money is going.

This is used to answer:

    WHERE DID MY MONEY GO?


The application can show:

    1. Rent
    2. Groceries
    3. Fuel
    4. Restaurants
    5. Shopping
===============================================================================
*/

CREATE OR REPLACE VIEW v_top_spending_categories AS

SELECT

    c.id AS category_id,

    c.name AS category,

    parent.name AS parent_category,

    SUM(t.amount) AS total_spent,

    COUNT(t.id) AS transaction_count

FROM transactions t

JOIN categories c

    ON c.id = t.category_id

LEFT JOIN categories parent

    ON parent.id = c.parent_id

WHERE t.transaction_type = 'EXPENSE'

GROUP BY

    c.id,

    c.name,

    parent.name

ORDER BY

    total_spent DESC;


/*
===============================================================================
7. CURRENT MONTH TOP SPENDING
===============================================================================

PURPOSE
-------

Shows your top expenses for THIS MONTH only.

Useful for the dashboard.

Example:

    Restaurants      NPR 3,500
    Fuel             NPR 3,000
    Shopping         NPR 2,500
===============================================================================
*/

CREATE OR REPLACE VIEW v_current_month_top_spending AS

SELECT

    c.name AS category,

    parent.name AS parent_category,

    SUM(t.amount) AS total_spent

FROM transactions t

JOIN categories c

    ON c.id = t.category_id

LEFT JOIN categories parent

    ON parent.id = c.parent_id

WHERE t.transaction_type = 'EXPENSE'

AND t.transaction_date >= DATE_TRUNC(
    'month',
    CURRENT_DATE
)

AND t.transaction_date < DATE_TRUNC(
    'month',
    CURRENT_DATE
) + INTERVAL '1 month'

GROUP BY

    c.name,

    parent.name

ORDER BY

    total_spent DESC;


/*
===============================================================================
8. CURRENT MONTH BUDGET ALERTS
===============================================================================

PURPOSE
-------

Shows categories where spending is:

    ON_TRACK
    WARNING
    OVER_BUDGET


ACTION:

    ON_TRACK
        Continue normally.

    WARNING
        Reduce spending.

    OVER_BUDGET
        Stop discretionary spending in this category.
===============================================================================
*/

CREATE OR REPLACE VIEW v_current_month_budget_alerts AS

SELECT *

FROM v_budget_vs_actual

WHERE month = DATE_TRUNC(
    'month',
    CURRENT_DATE
)::DATE

ORDER BY

    budget_used_percentage DESC;


/*
===============================================================================
9. SAVINGS GOALS DASHBOARD
===============================================================================

Shows progress toward financial goals.
===============================================================================
*/

CREATE OR REPLACE VIEW v_savings_dashboard AS

SELECT

    id,

    name,

    target_amount,

    saved_amount,

    remaining_amount,

    progress_percentage,

    target_date,

    status

FROM v_savings_goal_progress

ORDER BY

    progress_percentage DESC;


/*
===============================================================================
10. NET WORTH
===============================================================================

FORMULA:

    NET WORTH
    =
    TOTAL ASSETS
    -
    TOTAL LIABILITIES


Example:

    Bank + Cash = NPR 100,000

    Total Debt = NPR 143,590

    Net Worth = -NPR 43,590


IMPORTANT:

This is a simplified net worth calculation.

For a complete system, assets such as:

    Car
    Bike
    Land
    House
    Investments

should eventually be stored in an assets table.
===============================================================================
*/

CREATE OR REPLACE VIEW v_net_worth AS

WITH assets AS (

    SELECT

        COALESCE(
            SUM(calculated_balance),
            0
        ) AS total_assets

    FROM v_account_balances

),

liabilities AS (

    SELECT

        COALESCE(
            SUM(required_to_close),
            0
        ) AS total_liabilities

    FROM loans

    WHERE status = 'ACTIVE'

)

SELECT

    assets.total_assets,

    liabilities.total_liabilities,

    assets.total_assets
    -
    liabilities.total_liabilities
    AS net_worth

FROM assets

CROSS JOIN liabilities;


/*
===============================================================================
11. FINANCIAL DASHBOARD SUMMARY
===============================================================================

THIS IS THE MAIN DASHBOARD VIEW.

Your frontend can call:

    SELECT * FROM v_financial_dashboard;


It returns one row with the most important financial metrics.
===============================================================================
*/

CREATE OR REPLACE VIEW v_financial_dashboard AS

WITH current_cashflow AS (

    SELECT *

    FROM v_current_month_cashflow

),

account_balance AS (

    SELECT *

    FROM v_total_account_balance

),

debt AS (

    SELECT *

    FROM v_debt_dashboard

),

income_ratio AS (

    SELECT *

    FROM v_debt_to_income

),

networth AS (

    SELECT *

    FROM v_net_worth

)

SELECT

    CURRENT_DATE AS dashboard_date,

    current_cashflow.total_income,

    current_cashflow.total_expenses,

    current_cashflow.available_cashflow,

    account_balance.total_account_balance,

    debt.active_loan_count,

    debt.total_outstanding_principal,

    debt.total_required_to_close,

    debt.total_monthly_emi,

    income_ratio.debt_to_income_percentage,

    income_ratio.debt_status,

    networth.net_worth

FROM current_cashflow

CROSS JOIN account_balance

CROSS JOIN debt

CROSS JOIN income_ratio

CROSS JOIN networth;


/*
===============================================================================
12. FINANCIAL ACTION RECOMMENDATIONS
===============================================================================

This view turns financial data into ACTION.

Possible recommendations:

    REDUCE_SPENDING
    CONTROL_WANTS
    FOCUS_ON_DEBT
    BUILD_EMERGENCY_FUND
    INCREASE_SAVINGS
    HEALTHY_FINANCIAL_POSITION
===============================================================================
*/

CREATE OR REPLACE VIEW v_financial_actions AS

WITH cashflow AS (

    SELECT *

    FROM v_current_month_cashflow

),

debt AS (

    SELECT *

    FROM v_debt_dashboard

),

income_ratio AS (

    SELECT *

    FROM v_debt_to_income

)

SELECT

    CASE

        WHEN cashflow.available_cashflow < 0

            THEN 'STOP_SPENDING'

        WHEN income_ratio.debt_to_income_percentage >= 50

            THEN 'FOCUS_ON_DEBT'

        WHEN income_ratio.debt_to_income_percentage >= 35

            THEN 'REDUCE_DISCRETIONARY_SPENDING'

        WHEN cashflow.available_cashflow > 0

            THEN 'ALLOCATE_SURPLUS_TO_SAVINGS_OR_DEBT'

        ELSE 'REVIEW_FINANCES'

    END AS primary_action,

    CASE

        WHEN cashflow.available_cashflow < 0

            THEN 'Your expenses are higher than your income. Reduce non-essential spending immediately.'

        WHEN income_ratio.debt_to_income_percentage >= 50

            THEN 'More than 50% of your current income is committed to loan EMIs. Avoid new debt and prioritize debt reduction.'

        WHEN income_ratio.debt_to_income_percentage >= 35

            THEN 'Your debt obligations are significant. Control wants and avoid taking new loans.'

        WHEN cashflow.available_cashflow > 0

            THEN 'You have positive cashflow. Consider building an emergency fund and making extra debt payments.'

        ELSE 'Review your income and expenses to improve your monthly cashflow.'

    END AS action_description,

    cashflow.available_cashflow AS available_cashflow,

    debt.total_required_to_close,

    debt.total_monthly_emi,

    income_ratio.debt_to_income_percentage

FROM cashflow

CROSS JOIN debt

CROSS JOIN income_ratio;


/*
===============================================================================
13. FINAL DASHBOARD QUERY
===============================================================================

Run this query from your application.

===============================================================================
*/

SELECT *

FROM v_financial_dashboard;


/*
===============================================================================
14. ACTION QUERY
===============================================================================
*/

SELECT *

FROM v_financial_actions;


/*
===============================================================================
15. TOP SPENDING QUERY
===============================================================================
*/

SELECT *

FROM v_current_month_top_spending

LIMIT 10;


/*
===============================================================================
16. BUDGET ALERT QUERY
===============================================================================
*/

SELECT *

FROM v_current_month_budget_alerts

WHERE budget_status IN (
    'WARNING',
    'OVER_BUDGET'
);


/*
===============================================================================
17. LOAN PAYOFF QUERY
===============================================================================
*/

SELECT

    name,

    lender,

    required_to_close,

    outstanding_principal,

    emi_amount,

    interest_rate,

    status

FROM loans

WHERE status = 'ACTIVE'

ORDER BY

    required_to_close ASC;


/*
===============================================================================
DASHBOARD LOGIC
===============================================================================

The application should display something like:


    ==========================================================
                    PERSONAL FINANCE DASHBOARD
    ==========================================================

    CURRENT MONTH

    Income                 NPR 45,000
    Expenses               NPR 30,000
    Available Cashflow     NPR 15,000

    ----------------------------------------------------------

    MONEY

    Account Balance        NPR 100,000
    Net Worth              NPR -43,590

    ----------------------------------------------------------

    DEBT

    Total Debt             NPR 143,590
    Monthly EMI            NPR 14,206
    Debt-to-Income         31.57%

    Status                 MANAGEABLE

    ----------------------------------------------------------

    SPENDING

    #1 Rent                NPR 11,000
    #2 Groceries            NPR  8,000
    #3 Fuel                NPR  3,000
    #4 Restaurants          NPR  2,500

    ----------------------------------------------------------

    ACTION

    You have NPR 15,000 available cashflow.

    Recommended:

    1. Keep mandatory EMI payments.
    2. Maintain emergency savings.
    3. Use remaining surplus for extra debt repayment.
    4. Avoid new loans or unnecessary EMIs.

    ==========================================================


===============================================================================
END OF DASHBOARD SCRIPT
===============================================================================

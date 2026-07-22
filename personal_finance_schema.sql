/*
===============================================================================
PERSONAL FINANCE MANAGEMENT DATABASE
===============================================================================

PURPOSE
-------
This database is designed to answer four important financial questions:

1. WHERE DID MY MONEY GO?
   -> Track every income, expense, and transfer.

2. WHAT CAN I REDUCE?
   -> Compare actual spending against planned budgets.

3. HOW MUCH DEBT CAN I PAY?
   -> Track loans, EMIs, principal, interest, and extra payments.

4. HOW MUCH CAN I SAVE?
   -> Track savings, investments, net cash flow, and financial progress.


CORE FINANCIAL FLOW
-------------------

                    INCOME
                       |
                       v
              +----------------+
              |   ACCOUNTS     |
              | Bank / Wallet  |
              | Cash           |
              +----------------+
                       |
                       v
                 TRANSACTIONS
                 /     |      \
                /      |       \
               v       v        v
            EXPENSE  TRANSFER  SAVING
               |
               v
          CATEGORIES
               |
               v
            BUDGETS
               |
               v
         FINANCIAL REPORTS


                    LOANS
                      |
                      v
               LOAN PAYMENTS
                 /        \
                v          v
           PRINCIPAL     INTEREST
                |
                v
          DEBT REDUCTION


IMPORTANT PRINCIPLE
-------------------

A transaction represents ACTUAL MONEY MOVEMENT.

A budget represents PLANNED MONEY MOVEMENT.

A loan represents DEBT.

A loan payment represents a PAYMENT MADE TOWARD THAT DEBT.

An account represents WHERE YOUR MONEY CURRENTLY EXISTS.


DATABASE DESIGN
---------------

accounts
    -> Where is my money?

categories
    -> What is the money for?

transactions
    -> Where did money actually move?

budgets
    -> How much did I plan to spend?

loans
    -> What debt do I currently have?

loan_payments
    -> How much debt have I paid?

savings_goals
    -> What am I saving for?

savings_contributions
    -> How much have I saved toward each goal?

financial_snapshots
    -> How is my overall financial position changing?


===============================================================================
*/


/*
===============================================================================
1. EXTENSIONS
===============================================================================
*/

-- gen_random_uuid() is used to automatically generate UUID values.
CREATE EXTENSION IF NOT EXISTS pgcrypto;


/*
===============================================================================
2. ENUM TYPES
===============================================================================

ENUMs prevent invalid values from being inserted.

Example:
    account_type = 'BANK'
    account_type = 'WALLET'
    account_type = 'CASH'

Instead of allowing random values such as:
    'bank-account'
    'my-bank'
    'BANK ACCOUNT'

This keeps the database consistent.
===============================================================================
*/


CREATE TYPE account_type_enum AS ENUM (
    'BANK',
    'WALLET',
    'CASH',
    'CREDIT_CARD'
);


CREATE TYPE category_type_enum AS ENUM (
    'INCOME',
    'EXPENSE'
);


CREATE TYPE transaction_type_enum AS ENUM (
    'INCOME',
    'EXPENSE',
    'TRANSFER'
);


CREATE TYPE loan_status_enum AS ENUM (
    'ACTIVE',
    'PAID_OFF',
    'OVERDUE',
    'DEFAULTED',
    'CLOSED'
);


CREATE TYPE payment_type_enum AS ENUM (
    'EMI',
    'EXTRA_PAYMENT',
    'FULL_SETTLEMENT'
);


CREATE TYPE savings_goal_status_enum AS ENUM (
    'ACTIVE',
    'COMPLETED',
    'PAUSED',
    'CANCELLED'
);


/*
===============================================================================
3. ACCOUNTS
===============================================================================

PURPOSE
-------

Track WHERE YOUR MONEY IS.

Examples:

    Laxmi Sunrise Bank
    Kumari Bank
    eSewa
    Khalti
    Cash Wallet

IMPORTANT
---------

The account balance should represent the actual amount of money available
in that account.

Example:

    Laxmi Sunrise Bank = NPR 50,000
    eSewa              = NPR 2,000
    Cash               = NPR 1,000

Total available money = NPR 53,000


OPENING BALANCE
---------------

The opening_balance is the balance of the account when you first start
using this financial system.

All future transactions are tracked from this starting point.
===============================================================================
*/


CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Human-readable account name.
    -- Example: "Laxmi Sunrise Bank"
    name VARCHAR(100) NOT NULL,

    -- Type of account.
    -- BANK      = Bank account
    -- WALLET    = eSewa, Khalti, etc.
    -- CASH      = Physical cash
    -- CREDIT_CARD = Credit card account
    type account_type_enum NOT NULL,

    -- Money available in this account before tracking transactions.
    opening_balance NUMERIC(14,2) NOT NULL DEFAULT 0,

    -- Whether this account is currently being used.
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    -- Optional notes about the account.
    remarks TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT accounts_opening_balance_non_negative
        CHECK (opening_balance >= 0)
);


/*
===============================================================================
4. CATEGORIES
===============================================================================

PURPOSE
-------

Categories answer:

    "WHERE DID MY MONEY GO?"

Categories are hierarchical.

Example:

    EXPENSE
    |
    +-- Needs
    |   +-- Rent
    |   +-- Groceries
    |   +-- Electricity
    |   +-- Internet
    |   +-- Transportation
    |   +-- Fuel
    |   +-- Healthcare
    |
    +-- Wants
    |   +-- Restaurants
    |   +-- Entertainment
    |   +-- Shopping
    |   +-- Subscriptions
    |   +-- Gifts
    |
    +-- Financial
        +-- Loan EMI
        +-- Extra Loan Payment
        +-- Savings
        +-- Investment


PARENT / CHILD STRUCTURE
------------------------

Example:

    Needs
       |
       +-- Rent
       +-- Groceries
       +-- Fuel

"Needs" is the parent category.

"Rent", "Groceries", and "Fuel" are child categories.


This allows reports like:

    Total Needs = NPR 25,000

while also showing:

    Rent       = NPR 11,000
    Groceries  = NPR 8,000
    Fuel       = NPR 3,000


IMPORTANT
---------

Savings and Investments can be represented as categories for reporting
purposes, but the actual movement of money should also be recorded as
a TRANSFER to a savings/investment account when applicable.
===============================================================================
*/


CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Category name.
    name VARCHAR(100) NOT NULL,

    -- INCOME or EXPENSE.
    type category_type_enum NOT NULL,

    -- Parent category.
    -- NULL means this is a top-level category.
    parent_id UUID REFERENCES categories(id)
        ON DELETE RESTRICT,

    -- Optional description explaining how this category should be used.
    description TEXT,

    -- Whether the category is currently available for new transactions.
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Prevent duplicate category names under the same parent.
    CONSTRAINT unique_category_per_parent
        UNIQUE (name, parent_id)
);


/*
===============================================================================
5. TRANSACTIONS
===============================================================================

THIS IS THE MOST IMPORTANT TABLE.

PURPOSE
-------

This table records ACTUAL MONEY MOVEMENT.

Every transaction answers:

    WHEN did money move?
    HOW MUCH money moved?
    FROM WHICH ACCOUNT?
    WHAT WAS IT FOR?


TRANSACTION TYPES
-----------------

INCOME
------
Money coming into your financial system.

Examples:
    Salary
    Freelance income
    Bonus
    Interest income


EXPENSE
-------
Money leaving your financial system for consumption.

Examples:
    Rent
    Food
    Petrol
    Shopping


TRANSFER
--------
Money moving between your own accounts.

Examples:

    Bank -> eSewa
    Bank -> Cash
    Bank -> Savings Account

IMPORTANT:

A transfer is NOT an expense.

Example:

    You transfer NPR 10,000 from Bank to eSewa.

Your total wealth has not decreased.

Only the LOCATION of your money changed.


DESIGN NOTE
-----------

For a simple system, one transaction can represent a transfer.

For a more advanced double-entry system, transfers should have
two transaction records linked by a transfer_id.

This schema uses transfer_id so both sides can be linked.


AMOUNT
------

Always store the amount as a positive number.

The transaction_type determines whether it is:

    INCOME
    EXPENSE
    TRANSFER


Example:

    amount = 500

    EXPENSE -> money leaves account
    INCOME  -> money enters account
    TRANSFER -> money moves between accounts
===============================================================================
*/


CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Account where the transaction occurred.
    account_id UUID NOT NULL
        REFERENCES accounts(id)
        ON DELETE RESTRICT,

    -- Category explaining why the transaction occurred.
    category_id UUID
        REFERENCES categories(id)
        ON DELETE RESTRICT,

    -- Transaction amount.
    amount NUMERIC(14,2) NOT NULL,

    -- INCOME, EXPENSE, or TRANSFER.
    transaction_type transaction_type_enum NOT NULL,

    -- Optional description.
    -- Example: "Lunch at Pulchowk"
    description TEXT,

    -- Date when the financial event occurred.
    transaction_date DATE NOT NULL,

    -- Used to connect two sides of a transfer.
    transfer_id UUID,

    -- Optional external reference.
    -- Useful for bank statement imports.
    external_reference VARCHAR(255),

    -- Prevent duplicate imports.
    -- For example, the same bank transaction should not be imported twice.
    external_hash VARCHAR(255),

    -- Whether this transaction has been reconciled against the bank statement.
    is_reconciled BOOLEAN NOT NULL DEFAULT FALSE,

    -- Optional notes.
    remarks TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT transactions_amount_positive
        CHECK (amount > 0)
);


/*
===============================================================================
6. TRANSACTION INDEXES
===============================================================================

Indexes make financial reports faster.

Most common queries:

    Show all transactions for an account.

    Show all expenses for this month.

    Show spending by category.

    Show transactions between two dates.
===============================================================================
*/


CREATE INDEX idx_transactions_account_id
    ON transactions(account_id);


CREATE INDEX idx_transactions_category_id
    ON transactions(category_id);


CREATE INDEX idx_transactions_transaction_date
    ON transactions(transaction_date);


CREATE INDEX idx_transactions_type
    ON transactions(transaction_type);


CREATE INDEX idx_transactions_external_hash
    ON transactions(external_hash);


/*
===============================================================================
7. BUDGETS
===============================================================================

PURPOSE
-------

A budget tells you:

    "How much am I ALLOWED or PLANNING to spend?"

Transactions tell you:

    "How much did I ACTUALLY spend?"

The difference tells you:

    "Am I overspending?"


EXAMPLE
-------

Budget:

    Restaurants = NPR 2,000

Actual spending:

    Restaurants = NPR 3,500

Result:

    Overspent by NPR 1,500


ACTION
------

When spending reaches 80%:

    WARNING

When spending reaches 100%:

    BUDGET EXCEEDED


MONTH
-----

Store the first day of the month.

Example:

    2026-07-01

This represents the July 2026 budget.


IMPORTANT
---------

Budgets should normally be created for EXPENSE categories only.
===============================================================================
*/


CREATE TABLE budgets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Category being budgeted.
    category_id UUID NOT NULL
        REFERENCES categories(id)
        ON DELETE RESTRICT,

    -- First day of the budget month.
    -- Example: 2026-07-01 means July 2026.
    month DATE NOT NULL,

    -- Planned spending limit.
    budget_amount NUMERIC(14,2) NOT NULL,

    -- Optional notes.
    remarks TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT budgets_amount_positive
        CHECK (budget_amount >= 0),

    -- One budget per category per month.
    CONSTRAINT unique_budget_category_month
        UNIQUE (category_id, month)
);


/*
===============================================================================
8. LOANS
===============================================================================

PURPOSE
-------

Loans are tracked separately from normal expenses.

A loan has:

    Original amount
    Outstanding principal
    Interest rate
    EMI
    Next payment date
    Closing amount


EXAMPLE
-------

BIKE LOAN

    Disbursed Amount        = NPR 196,450
    Outstanding Principal   = NPR 91,528.42
    Required To Close       = NPR 92,479.46
    EMI                     = NPR 6,524.95


PHONE LOAN

    Required To Close       = NPR 51,110.51
    EMI                     = NPR 7,681.09


IMPORTANT
---------

Do not simply record the entire EMI as "interest".

An EMI usually contains:

    Principal portion
    Interest portion
    Possible fees


This is why loan_payments exists separately.


ACTIONABLE PURPOSE
------------------

This table helps answer:

    How much debt do I have?

    How much do I need to close my loans?

    How much do I pay every month?

    Which loan should I pay first?

    How much debt did I eliminate this month?
===============================================================================
*/


CREATE TABLE loans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Friendly loan name.
    -- Example: "Bike Loan"
    name VARCHAR(100) NOT NULL,

    -- Financial institution.
    -- Example: "Hulas Finserv"
    lender VARCHAR(150),

    -- Original amount given by the lender.
    disbursed_amount NUMERIC(14,2),

    -- Remaining unpaid principal.
    outstanding_principal NUMERIC(14,2),

    -- Amount currently required to fully close the loan.
    required_to_close NUMERIC(14,2),

    -- Regular monthly EMI.
    emi_amount NUMERIC(14,2),

    -- Annual interest rate, if known.
    interest_rate NUMERIC(7,4),

    -- Date of next scheduled installment.
    next_payment_date DATE,

    -- Current loan status.
    status loan_status_enum NOT NULL DEFAULT 'ACTIVE',

    -- Date the loan was started.
    start_date DATE,

    -- Expected or actual closing date.
    close_date DATE,

    -- Optional loan account/reference number.
    loan_reference VARCHAR(100),

    -- Product financed.
    -- Example: "Pulsar 150"
    product_name VARCHAR(150),

    -- Dealer or seller.
    dealer_name VARCHAR(150),

    -- Optional notes.
    remarks TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT loans_disbursed_non_negative
        CHECK (
            disbursed_amount IS NULL
            OR disbursed_amount >= 0
        ),

    CONSTRAINT loans_principal_non_negative
        CHECK (
            outstanding_principal IS NULL
            OR outstanding_principal >= 0
        ),

    CONSTRAINT loans_close_amount_non_negative
        CHECK (
            required_to_close IS NULL
            OR required_to_close >= 0
        ),

    CONSTRAINT loans_emi_non_negative
        CHECK (
            emi_amount IS NULL
            OR emi_amount >= 0
        )
);


/*
===============================================================================
9. LOAN PAYMENTS
===============================================================================

PURPOSE
-------

Track every payment made toward a loan.

Example:

    Bike EMI
    NPR 6,524.95


A payment can contain:

    Principal paid
    Interest paid
    Fees


EXAMPLE
-------

EMI:

    Total Payment       = NPR 6,524.95
    Principal           = NPR 5,622.20
    Interest            = NPR 890.24
    Fees                = NPR 12.51


This allows you to understand:

    How much debt did I actually reduce?

versus:

    How much did I pay in interest?


IMPORTANT
---------

The loan payment should normally also have a corresponding transaction.

Example:

    Loan Payment
         |
         +-- Loan record
         |
         +-- Transaction record
                  |
                  +-- Money leaves bank account


This keeps your cashflow and debt records synchronized.
===============================================================================
*/


CREATE TABLE loan_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Loan being paid.
    loan_id UUID NOT NULL
        REFERENCES loans(id)
        ON DELETE RESTRICT,

    -- Optional transaction that represents the actual money leaving
    -- the bank/wallet account.
    transaction_id UUID
        REFERENCES transactions(id)
        ON DELETE SET NULL,

    -- EMI, extra payment, or full settlement.
    payment_type payment_type_enum NOT NULL,

    -- Total amount paid.
    payment_amount NUMERIC(14,2) NOT NULL,

    -- Portion that reduced the principal.
    principal_paid NUMERIC(14,2) NOT NULL DEFAULT 0,

    -- Interest paid.
    interest_paid NUMERIC(14,2) NOT NULL DEFAULT 0,

    -- Additional fees or charges.
    fees_paid NUMERIC(14,2) NOT NULL DEFAULT 0,

    -- Date payment was made.
    payment_date DATE NOT NULL,

    -- Optional notes.
    remarks TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT loan_payment_amount_positive
        CHECK (payment_amount > 0),

    CONSTRAINT loan_payment_principal_non_negative
        CHECK (principal_paid >= 0),

    CONSTRAINT loan_payment_interest_non_negative
        CHECK (interest_paid >= 0),

    CONSTRAINT loan_payment_fees_non_negative
        CHECK (fees_paid >= 0),

    -- Payment components should not exceed total payment.
    CONSTRAINT loan_payment_components_valid
        CHECK (
            principal_paid
            + interest_paid
            + fees_paid
            <= payment_amount
        )
);


/*
===============================================================================
10. SAVINGS GOALS
===============================================================================

PURPOSE
-------

Savings goals answer:

    "What am I saving for?"

Examples:

    Emergency Fund
    New Car
    House Down Payment
    Land Purchase
    Education
    Travel


EXAMPLE
-------

Goal:

    Emergency Fund

Target:

    NPR 300,000

Current:

    NPR 100,000

Progress:

    33.33%


ACTION
------

The system should tell you:

    Target Amount
    Current Saved
    Remaining
    Progress %
    Target Date
===============================================================================
*/


CREATE TABLE savings_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Name of the savings goal.
    name VARCHAR(150) NOT NULL,

    -- Total amount you want to save.
    target_amount NUMERIC(14,2) NOT NULL,

    -- Current amount saved toward the goal.
    current_amount NUMERIC(14,2) NOT NULL DEFAULT 0,

    -- Target date.
    target_date DATE,

    -- Goal status.
    status savings_goal_status_enum NOT NULL DEFAULT 'ACTIVE',

    -- Optional description.
    description TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT savings_target_positive
        CHECK (target_amount > 0),

    CONSTRAINT savings_current_non_negative
        CHECK (current_amount >= 0)
);


/*
===============================================================================
11. SAVINGS CONTRIBUTIONS
===============================================================================

PURPOSE
-------

Track every contribution toward a savings goal.

Example:

    Emergency Fund

    July 1  -> NPR 5,000
    July 15 -> NPR 3,000

Total:

    NPR 8,000


This allows you to see your savings behavior over time.
===============================================================================
*/


CREATE TABLE savings_contributions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Goal receiving the contribution.
    savings_goal_id UUID NOT NULL
        REFERENCES savings_goals(id)
        ON DELETE RESTRICT,

    -- Account from which money was moved.
    account_id UUID
        REFERENCES accounts(id)
        ON DELETE RESTRICT,

    -- Optional transaction representing the money movement.
    transaction_id UUID
        REFERENCES transactions(id)
        ON DELETE SET NULL,

    -- Contribution amount.
    amount NUMERIC(14,2) NOT NULL,

    -- Date of contribution.
    contribution_date DATE NOT NULL,

    -- Optional notes.
    remarks TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT savings_contribution_positive
        CHECK (amount > 0)
);


/*
===============================================================================
12. FINANCIAL SNAPSHOTS
===============================================================================

PURPOSE
-------

Store your financial position at a specific point in time.

Example:

    July 31, 2026

    Total Cash        = NPR 100,000
    Total Debt        = NPR 140,000
    Net Worth         = NPR -40,000


This allows you to track your financial progress month by month.

IMPORTANT
---------

This table is a SNAPSHOT.

It should not be treated as the source of truth.

The actual source of truth is:

    Accounts
    Transactions
    Loans
    Loan Payments

Snapshots are useful for historical reporting.
===============================================================================
*/


CREATE TABLE financial_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Snapshot date.
    snapshot_date DATE NOT NULL,

    -- Total money across all accounts.
    total_assets NUMERIC(14,2) NOT NULL DEFAULT 0,

    -- Total outstanding debt.
    total_liabilities NUMERIC(14,2) NOT NULL DEFAULT 0,

    -- Assets - Liabilities.
    net_worth NUMERIC(14,2)
        GENERATED ALWAYS AS (
            total_assets - total_liabilities
        ) STORED,

    -- Total income during the period.
    total_income NUMERIC(14,2) NOT NULL DEFAULT 0,

    -- Total expenses during the period.
    total_expenses NUMERIC(14,2) NOT NULL DEFAULT 0,

    -- Amount paid toward loan principal.
    total_debt_payment NUMERIC(14,2) NOT NULL DEFAULT 0,

    -- Amount saved/invested.
    total_savings NUMERIC(14,2) NOT NULL DEFAULT 0,

    -- Optional notes.
    remarks TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_snapshot_date
        UNIQUE (snapshot_date)
);


/*
===============================================================================
13. USEFUL INDEXES FOR LOANS AND SAVINGS
===============================================================================
*/


CREATE INDEX idx_loans_status
    ON loans(status);


CREATE INDEX idx_loans_next_payment_date
    ON loans(next_payment_date);


CREATE INDEX idx_loan_payments_loan_id
    ON loan_payments(loan_id);


CREATE INDEX idx_loan_payments_payment_date
    ON loan_payments(payment_date);


CREATE INDEX idx_savings_contributions_goal_id
    ON savings_contributions(savings_goal_id);


CREATE INDEX idx_savings_contributions_date
    ON savings_contributions(contribution_date);


/*
===============================================================================
14. SEED TOP-LEVEL CATEGORIES
===============================================================================

These are parent categories.

Example:

    Needs
    Wants
    Financial
===============================================================================
*/


INSERT INTO categories (name, type, parent_id, description)
VALUES
(
    'Needs',
    'EXPENSE',
    NULL,
    'Essential expenses required for normal living.'
),
(
    'Wants',
    'EXPENSE',
    NULL,
    'Discretionary expenses that can be reduced or eliminated.'
),
(
    'Financial',
    'EXPENSE',
    NULL,
    'Financial priorities such as debt payments, savings, and investments.'
);


/*
===============================================================================
15. SEED EXPENSE CATEGORIES
===============================================================================
*/


-- NEEDS
INSERT INTO categories (name, type, parent_id, description)
SELECT
    category_name,
    'EXPENSE',
    id,
    description
FROM categories
JOIN (
    VALUES
        ('Rent', 'Housing expense.'),
        ('Groceries', 'Food and household essentials.'),
        ('Electricity', 'Electricity and utility bills.'),
        ('Internet', 'Internet and communication expenses.'),
        ('Transportation', 'Public transportation and other travel.'),
        ('Fuel', 'Petrol, diesel, or vehicle charging.'),
        ('Healthcare', 'Medical and health-related expenses.')
) AS child(category_name, description)
ON categories.name = 'Needs'
AND categories.parent_id IS NULL;


-- WANTS
INSERT INTO categories (name, type, parent_id, description)
SELECT
    category_name,
    'EXPENSE',
    id,
    description
FROM categories
JOIN (
    VALUES
        ('Restaurants', 'Eating out and food delivery.'),
        ('Entertainment', 'Movies, games, events, and leisure.'),
        ('Shopping', 'Non-essential shopping.'),
        ('Subscriptions', 'Digital and recurring subscriptions.'),
        ('Gifts', 'Gifts and personal contributions.')
) AS child(category_name, description)
ON categories.name = 'Wants'
AND categories.parent_id IS NULL;


-- FINANCIAL
INSERT INTO categories (name, type, parent_id, description)
SELECT
    category_name,
    'EXPENSE',
    id,
    description
FROM categories
JOIN (
    VALUES
        ('Loan EMI', 'Regular scheduled loan payments.'),
        ('Extra Loan Payment', 'Additional payment made to reduce debt faster.'),
        ('Savings', 'Money allocated toward savings goals.'),
        ('Investment', 'Money allocated toward investments.')
) AS child(category_name, description)
ON categories.name = 'Financial'
AND categories.parent_id IS NULL;


/*
===============================================================================
16. INCOME CATEGORIES
===============================================================================
*/


INSERT INTO categories (
    name,
    type,
    parent_id,
    description
)
VALUES
(
    'Salary',
    'INCOME',
    NULL,
    'Regular employment income.'
),
(
    'Freelance',
    'INCOME',
    NULL,
    'Income from freelance or side projects.'
),
(
    'Business Income',
    'INCOME',
    NULL,
    'Income generated from business activities.'
),
(
    'Bonus',
    'INCOME',
    NULL,
    'Performance bonuses and one-time income.'
),
(
    'Interest Income',
    'INCOME',
    NULL,
    'Interest received from bank deposits or investments.'
),
(
    'Other Income',
    'INCOME',
    NULL,
    'Other income that does not fit into the main categories.'
);


/*
===============================================================================
17. VIEW: ACCOUNT BALANCES
===============================================================================

PURPOSE
-------

Calculate current account balances.

Formula:

    Opening Balance
    + Income
    - Expense

Transfers require special handling because they move money between accounts.

This basic view calculates the balance based on income and expenses.
A production application should maintain both sides of transfers.
===============================================================================
*/


CREATE OR REPLACE VIEW v_account_balances AS
SELECT
    a.id,
    a.name,
    a.type,
    a.opening_balance,

    COALESCE(
        SUM(
            CASE
                WHEN t.transaction_type = 'INCOME'
                    THEN t.amount
                WHEN t.transaction_type = 'EXPENSE'
                    THEN -t.amount
                ELSE 0
            END
        ),
        0
    ) AS net_transaction_amount,

    a.opening_balance
    +
    COALESCE(
        SUM(
            CASE
                WHEN t.transaction_type = 'INCOME'
                    THEN t.amount
                WHEN t.transaction_type = 'EXPENSE'
                    THEN -t.amount
                ELSE 0
            END
        ),
        0
    ) AS calculated_balance

FROM accounts a

LEFT JOIN transactions t
    ON t.account_id = a.id

GROUP BY
    a.id,
    a.name,
    a.type,
    a.opening_balance;


/*
===============================================================================
18. VIEW: MONTHLY SPENDING BY CATEGORY
===============================================================================

PURPOSE
-------

Answer:

    "Where did my money go?"

This view groups expenses by month and category.
===============================================================================
*/


CREATE OR REPLACE VIEW v_monthly_category_spending AS
SELECT
    DATE_TRUNC(
        'month',
        t.transaction_date
    )::DATE AS month,

    c.name AS category,

    t.amount

FROM transactions t

JOIN categories c
    ON c.id = t.category_id

WHERE t.transaction_type = 'EXPENSE';


/*
===============================================================================
19. VIEW: BUDGET VS ACTUAL
===============================================================================

PURPOSE
-------

Answer:

    "What can I reduce?"

Shows:

    Budget
    Actual spending
    Remaining amount
    Percentage used


ACTION RULES
------------

0% - 79%
    Normal

80% - 99%
    Warning

100%+
    Over budget
===============================================================================
*/


CREATE OR REPLACE VIEW v_budget_vs_actual AS
SELECT

    b.id AS budget_id,

    b.month,

    c.name AS category,

    b.budget_amount,

    COALESCE(
        SUM(t.amount),
        0
    ) AS actual_spending,

    b.budget_amount
    -
    COALESCE(
        SUM(t.amount),
        0
    ) AS remaining_budget,

    CASE
        WHEN b.budget_amount = 0 THEN 0
        ELSE ROUND(
            (
                COALESCE(SUM(t.amount), 0)
                / b.budget_amount
            ) * 100,
            2
        )
    END AS budget_used_percentage,

    CASE
        WHEN COALESCE(SUM(t.amount), 0)
             >= b.budget_amount
            THEN 'OVER_BUDGET'

        WHEN COALESCE(SUM(t.amount), 0)
             >= b.budget_amount * 0.80
            THEN 'WARNING'

        ELSE 'ON_TRACK'
    END AS budget_status

FROM budgets b

JOIN categories c
    ON c.id = b.category_id

LEFT JOIN transactions t
    ON t.category_id = b.category_id
    AND t.transaction_type = 'EXPENSE'
    AND t.transaction_date >= b.month
    AND t.transaction_date < b.month + INTERVAL '1 month'

GROUP BY
    b.id,
    b.month,
    c.name,
    b.budget_amount;


/*
===============================================================================
20. VIEW: LOAN SUMMARY
===============================================================================

PURPOSE
-------

Answer:

    "How much debt do I have?"

    "How much have I paid?"

    "How much principal have I reduced?"

    "How much interest have I paid?"
===============================================================================
*/


CREATE OR REPLACE VIEW v_loan_summary AS
SELECT

    l.id,

    l.name,

    l.lender,

    l.disbursed_amount,

    l.outstanding_principal,

    l.required_to_close,

    l.emi_amount,

    l.interest_rate,

    l.next_payment_date,

    l.status,

    COALESCE(
        SUM(lp.payment_amount),
        0
    ) AS total_paid,

    COALESCE(
        SUM(lp.principal_paid),
        0
    ) AS total_principal_paid,

    COALESCE(
        SUM(lp.interest_paid),
        0
    ) AS total_interest_paid,

    COALESCE(
        SUM(lp.fees_paid),
        0
    ) AS total_fees_paid

FROM loans l

LEFT JOIN loan_payments lp
    ON lp.loan_id = l.id

GROUP BY
    l.id;


/*
===============================================================================
21. VIEW: MONTHLY CASHFLOW
===============================================================================

PURPOSE
-------

Answer:

    "How much money did I earn?"

    "How much did I spend?"

    "How much money is left?"

Formula:

    Net Cashflow = Income - Expenses
===============================================================================
*/


CREATE OR REPLACE VIEW v_monthly_cashflow AS
SELECT

    DATE_TRUNC(
        'month',
        transaction_date
    )::DATE AS month,

    SUM(
        CASE
            WHEN transaction_type = 'INCOME'
                THEN amount
            ELSE 0
        END
    ) AS total_income,

    SUM(
        CASE
            WHEN transaction_type = 'EXPENSE'
                THEN amount
            ELSE 0
        END
    ) AS total_expenses,

    SUM(
        CASE
            WHEN transaction_type = 'INCOME'
                THEN amount
            WHEN transaction_type = 'EXPENSE'
                THEN -amount
            ELSE 0
        END
    ) AS net_cashflow

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
22. VIEW: TOTAL DEBT
===============================================================================

PURPOSE
-------

Quickly see total outstanding debt.

This is one of the most important financial metrics.
===============================================================================
*/


CREATE OR REPLACE VIEW v_total_debt AS
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
23. VIEW: SAVINGS GOAL PROGRESS
===============================================================================

PURPOSE
-------

Answer:

    "How much have I saved?"

    "How much more do I need?"

    "Am I on track?"
===============================================================================
*/


CREATE OR REPLACE VIEW v_savings_goal_progress AS
SELECT

    sg.id,

    sg.name,

    sg.target_amount,

    COALESCE(
        SUM(sc.amount),
        sg.current_amount
    ) AS saved_amount,

    sg.target_amount
    -
    COALESCE(
        SUM(sc.amount),
        sg.current_amount
    ) AS remaining_amount,

    CASE
        WHEN sg.target_amount = 0
            THEN 0

        ELSE ROUND(
            (
                COALESCE(
                    SUM(sc.amount),
                    sg.current_amount
                )
                /
                sg.target_amount
            ) * 100,
            2
        )
    END AS progress_percentage,

    sg.target_date,

    sg.status

FROM savings_goals sg

LEFT JOIN savings_contributions sc
    ON sc.savings_goal_id = sg.id

GROUP BY
    sg.id;


/*
===============================================================================
24. ACTIONABLE FINANCIAL QUESTIONS
===============================================================================

These queries are designed to help you TAKE ACTION.

===============================================================================
*/


/*
------------------------------------------------------------------------------
QUESTION 1:
WHERE DID MY MONEY GO THIS MONTH?
------------------------------------------------------------------------------

Replace '2026-07-01' with the first day of the month you want to analyze.
*/


SELECT
    c.name AS category,
    SUM(t.amount) AS total_spent

FROM transactions t

JOIN categories c
    ON c.id = t.category_id

WHERE t.transaction_type = 'EXPENSE'

AND t.transaction_date >= '2026-07-01'

AND t.transaction_date < '2026-08-01'

GROUP BY
    c.name

ORDER BY
    total_spent DESC;


/*
------------------------------------------------------------------------------
QUESTION 2:
WHAT CAN I REDUCE?

Look at WANT categories and find the largest expenses.
-------------------------------------------------------------------------------
*/


SELECT
    c.name AS category,
    SUM(t.amount) AS total_spent

FROM transactions t

JOIN categories c
    ON c.id = t.category_id

JOIN categories parent
    ON parent.id = c.parent_id

WHERE t.transaction_type = 'EXPENSE'

AND parent.name = 'Wants'

GROUP BY
    c.name

ORDER BY
    total_spent DESC;


/*
------------------------------------------------------------------------------
QUESTION 3:
WHICH BUDGETS ARE OVERSPENT?
-------------------------------------------------------------------------------
*/


SELECT *

FROM v_budget_vs_actual

WHERE budget_status = 'OVER_BUDGET'

ORDER BY
    remaining_budget ASC;


/*
------------------------------------------------------------------------------
QUESTION 4:
HOW MUCH DEBT DO I HAVE?
-------------------------------------------------------------------------------
*/


SELECT *

FROM v_total_debt;


/*
------------------------------------------------------------------------------
QUESTION 5:
WHICH LOAN SHOULD I PRIORITIZE?
-------------------------------------------------------------------------------

Generally:

    1. Highest interest rate first
    OR
    2. Smallest balance first

This query shows loans by highest interest rate.
-------------------------------------------------------------------------------
*/


SELECT

    name,

    lender,

    required_to_close,

    outstanding_principal,

    emi_amount,

    interest_rate

FROM loans

WHERE status = 'ACTIVE'

ORDER BY
    interest_rate DESC NULLS LAST;


/*
------------------------------------------------------------------------------
QUESTION 6:
HOW MUCH DEBT DID I REDUCE?
-------------------------------------------------------------------------------
*/


SELECT

    DATE_TRUNC(
        'month',
        payment_date
    )::DATE AS month,

    SUM(principal_paid) AS principal_reduced,

    SUM(interest_paid) AS interest_paid,

    SUM(payment_amount) AS total_paid

FROM loan_payments

GROUP BY
    DATE_TRUNC(
        'month',
        payment_date
    )::DATE

ORDER BY
    month;


/*
------------------------------------------------------------------------------
QUESTION 7:
HOW MUCH CAN I SAVE?

Net savings potential:

    Income - Expenses

This does not include transfers between your own accounts.
-------------------------------------------------------------------------------
*/


SELECT

    DATE_TRUNC(
        'month',
        transaction_date
    )::DATE AS month,

    SUM(
        CASE
            WHEN transaction_type = 'INCOME'
                THEN amount
            ELSE 0
        END
    ) AS income,

    SUM(
        CASE
            WHEN transaction_type = 'EXPENSE'
                THEN amount
            ELSE 0
        END
    ) AS expenses,

    SUM(
        CASE
            WHEN transaction_type = 'INCOME'
                THEN amount
            WHEN transaction_type = 'EXPENSE'
                THEN -amount
            ELSE 0
        END
    ) AS potential_savings

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
25. FINANCIAL MANAGEMENT ACTION PLAN
===============================================================================

EVERY DAY
----------

1. Record every expense.

    -> Food
    -> Fuel
    -> Shopping
    -> Coffee
    -> Online purchases

2. Do not ignore small expenses.

    NPR 100 x 30 days = NPR 3,000/month.


EVERY WEEK
----------

Review:

    Top 5 spending categories.

Ask:

    "What can I reduce next week?"


EVERY MONTH
-----------

Step 1:
    Record total income.

Step 2:
    Review total expenses.

Step 3:
    Compare budget vs actual.

Step 4:
    Identify unnecessary spending.

Step 5:
    Pay all mandatory EMIs.

Step 6:
    Make extra loan payment if possible.

Step 7:
    Allocate money to savings.

Step 8:
    Record financial snapshot.


===============================================================================
DEBT PAYOFF STRATEGY
===============================================================================

Recommended order:

1. Never miss mandatory EMI payments.

2. Maintain a small emergency fund.

3. Identify the loan with the highest effective interest rate.

4. Direct extra money toward that loan.

5. When one loan is fully paid:

       Old EMI
          |
          v
       Extra payment toward next loan

6. Continue until all debt is cleared.


===============================================================================
EXPENSE CONTROL STRATEGY
===============================================================================

The system should classify spending into:

    NEEDS
    WANTS
    FINANCIAL


NEEDS
------

These are essential.

Action:

    Optimize.

Example:

    Reduce unnecessary fuel usage.
    Find cheaper internet plan.
    Control grocery waste.


WANTS
-----

These are the first expenses to reduce.

Action:

    Set strict budgets.

Example:

    Restaurants = NPR 2,000/month.

If spending reaches NPR 2,000:

    Stop discretionary restaurant spending.


FINANCIAL
---------

These are expenses that improve your financial future.

Action:

    Prioritize.

Examples:

    Loan principal reduction.
    Emergency savings.
    Investments.


===============================================================================
THE MAIN FINANCIAL LOOP
===============================================================================


             EARN MONEY
                  |
                  v
           RECORD INCOME
                  |
                  v
         PAY NECESSARY EXPENSES
                  |
                  v
           PAY LOAN EMI
                  |
                  v
         REVIEW BUDGET STATUS
                  |
                  v
      REDUCE UNNECESSARY SPENDING
                  |
                  v
       EXTRA LOAN PAYMENT
                  |
                  v
             SAVE MONEY
                  |
                  v
         BUILD EMERGENCY FUND
                  |
                  v
            INVEST MONEY
                  |
                  v
          INCREASE NET WORTH


===============================================================================
FINAL GOAL
===============================================================================

The database should help you move from:

    "I don't know where my money went."

TO:

    "I know exactly where my money went."

Then:

    "I know which expenses I can reduce."

Then:

    "I know exactly how much extra I can pay toward my loans."

Then:

    "I know exactly how much I can save."

Finally:

    "I know whether my net worth is improving every month."


===============================================================================
END OF SCHEMA
===============================================================================

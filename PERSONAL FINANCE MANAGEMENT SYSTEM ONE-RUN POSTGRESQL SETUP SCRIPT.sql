/*
===============================================================================
PERSONAL FINANCE MANAGEMENT SYSTEM
ONE-RUN POSTGRESQL SETUP SCRIPT
===============================================================================

PURPOSE
-------

This script creates a complete personal finance management database.

The system answers four questions:

1. WHERE DID MY MONEY GO?
2. WHAT CAN I REDUCE?
3. HOW MUCH DEBT CAN I PAY?
4. HOW MUCH CAN I SAVE?


IMPORTANT
---------

Run this script inside your target PostgreSQL database.

Example:

    CREATE DATABASE personal_finance;

Then connect to:

    personal_finance

And run this script.


===============================================================================
*/


/*
===============================================================================
STEP 1: EXTENSIONS
===============================================================================
*/

CREATE EXTENSION IF NOT EXISTS pgcrypto;


/*
===============================================================================
STEP 2: ENUM TYPES
===============================================================================
*/

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'account_type_enum'
    ) THEN

        CREATE TYPE account_type_enum AS ENUM (
            'BANK',
            'WALLET',
            'CASH',
            'CREDIT_CARD'
        );

    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'category_type_enum'
    ) THEN

        CREATE TYPE category_type_enum AS ENUM (
            'INCOME',
            'EXPENSE'
        );

    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'transaction_type_enum'
    ) THEN

        CREATE TYPE transaction_type_enum AS ENUM (
            'INCOME',
            'EXPENSE',
            'TRANSFER'
        );

    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'loan_status_enum'
    ) THEN

        CREATE TYPE loan_status_enum AS ENUM (
            'ACTIVE',
            'PAID_OFF',
            'OVERDUE',
            'DEFAULTED',
            'CLOSED'
        );

    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'payment_type_enum'
    ) THEN

        CREATE TYPE payment_type_enum AS ENUM (
            'EMI',
            'EXTRA_PAYMENT',
            'FULL_SETTLEMENT'
        );

    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'savings_goal_status_enum'
    ) THEN

        CREATE TYPE savings_goal_status_enum AS ENUM (
            'ACTIVE',
            'COMPLETED',
            'PAUSED',
            'CANCELLED'
        );

    END IF;

END
$$;


/*
===============================================================================
STEP 3: ACCOUNTS
===============================================================================

Stores where your money currently exists.

Examples:

    Laxmi Sunrise Bank
    Kumari Bank
    eSewa
    Khalti
    Cash
===============================================================================
*/

CREATE TABLE IF NOT EXISTS accounts (

    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name VARCHAR(100) NOT NULL,

    type account_type_enum NOT NULL,

    opening_balance NUMERIC(14,2)
        NOT NULL DEFAULT 0,

    is_active BOOLEAN
        NOT NULL DEFAULT TRUE,

    remarks TEXT,

    created_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT accounts_opening_balance_non_negative
        CHECK (opening_balance >= 0)

);


/*
===============================================================================
STEP 4: CATEGORIES
===============================================================================

Used to answer:

    WHERE DID MY MONEY GO?

Hierarchy:

    Needs
        Rent
        Groceries
        Fuel

    Wants
        Restaurants
        Entertainment
        Shopping

    Financial
        Loan EMI
        Extra Loan Payment
        Savings
        Investment
===============================================================================
*/

CREATE TABLE IF NOT EXISTS categories (

    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name VARCHAR(100) NOT NULL,

    type category_type_enum NOT NULL,

    parent_id UUID
        REFERENCES categories(id)
        ON DELETE RESTRICT,

    description TEXT,

    is_active BOOLEAN
        NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_category_per_parent
        UNIQUE (name, parent_id)

);


/*
===============================================================================
STEP 5: TRANSACTIONS
===============================================================================

The most important financial table.

Stores actual money movement.

Types:

    INCOME
    EXPENSE
    TRANSFER


Examples:

    Salary                 -> INCOME
    Restaurant              -> EXPENSE
    Petrol                  -> EXPENSE
    Bank -> eSewa           -> TRANSFER
===============================================================================
*/

CREATE TABLE IF NOT EXISTS transactions (

    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    account_id UUID NOT NULL
        REFERENCES accounts(id)
        ON DELETE RESTRICT,

    category_id UUID
        REFERENCES categories(id)
        ON DELETE RESTRICT,

    amount NUMERIC(14,2) NOT NULL,

    transaction_type transaction_type_enum NOT NULL,

    description TEXT,

    transaction_date DATE NOT NULL,

    transfer_id UUID,

    external_reference VARCHAR(255),

    external_hash VARCHAR(255),

    is_reconciled BOOLEAN
        NOT NULL DEFAULT FALSE,

    remarks TEXT,

    created_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT transactions_amount_positive
        CHECK (amount > 0)

);


/*
===============================================================================
STEP 6: BUDGETS
===============================================================================

Controls your spending.

Example:

    Restaurants Budget = NPR 2,000

Actual Spending       = NPR 3,500

Result:

    Over Budget = NPR 1,500
===============================================================================
*/

CREATE TABLE IF NOT EXISTS budgets (

    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    category_id UUID NOT NULL
        REFERENCES categories(id)
        ON DELETE RESTRICT,

    month DATE NOT NULL,

    budget_amount NUMERIC(14,2)
        NOT NULL,

    remarks TEXT,

    created_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT budgets_amount_non_negative
        CHECK (budget_amount >= 0),

    CONSTRAINT unique_budget_category_month
        UNIQUE (category_id, month)

);


/*
===============================================================================
STEP 7: LOANS
===============================================================================

Stores all debt.

Examples:

    Bike Loan
    Phone Loan

This table stores loan information.

Actual payments are stored separately in loan_payments.
===============================================================================
*/

CREATE TABLE IF NOT EXISTS loans (

    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name VARCHAR(100) NOT NULL,

    lender VARCHAR(150),

    disbursed_amount NUMERIC(14,2),

    outstanding_principal NUMERIC(14,2),

    required_to_close NUMERIC(14,2),

    emi_amount NUMERIC(14,2),

    interest_rate NUMERIC(7,4),

    next_payment_date DATE,

    status loan_status_enum
        NOT NULL DEFAULT 'ACTIVE',

    start_date DATE,

    close_date DATE,

    loan_reference VARCHAR(100),

    product_name VARCHAR(150),

    dealer_name VARCHAR(150),

    remarks TEXT,

    created_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

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
STEP 8: LOAN PAYMENTS
===============================================================================

Tracks every loan payment.

Example:

    EMI = NPR 6,524.95

    Principal = NPR 5,622.20
    Interest  = NPR 890.24
    Fees      = NPR 12.51
===============================================================================
*/

CREATE TABLE IF NOT EXISTS loan_payments (

    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    loan_id UUID NOT NULL
        REFERENCES loans(id)
        ON DELETE RESTRICT,

    transaction_id UUID
        REFERENCES transactions(id)
        ON DELETE SET NULL,

    payment_type payment_type_enum NOT NULL,

    payment_amount NUMERIC(14,2) NOT NULL,

    principal_paid NUMERIC(14,2)
        NOT NULL DEFAULT 0,

    interest_paid NUMERIC(14,2)
        NOT NULL DEFAULT 0,

    fees_paid NUMERIC(14,2)
        NOT NULL DEFAULT 0,

    payment_date DATE NOT NULL,

    remarks TEXT,

    created_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT loan_payment_amount_positive
        CHECK (payment_amount > 0),

    CONSTRAINT loan_payment_principal_non_negative
        CHECK (principal_paid >= 0),

    CONSTRAINT loan_payment_interest_non_negative
        CHECK (interest_paid >= 0),

    CONSTRAINT loan_payment_fees_non_negative
        CHECK (fees_paid >= 0)

);


/*
===============================================================================
STEP 9: SAVINGS GOALS
===============================================================================

Examples:

    Emergency Fund
    House
    Car
    Land
    Education
===============================================================================
*/

CREATE TABLE IF NOT EXISTS savings_goals (

    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name VARCHAR(150) NOT NULL,

    target_amount NUMERIC(14,2) NOT NULL,

    current_amount NUMERIC(14,2)
        NOT NULL DEFAULT 0,

    target_date DATE,

    status savings_goal_status_enum
        NOT NULL DEFAULT 'ACTIVE',

    description TEXT,

    created_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT savings_target_positive
        CHECK (target_amount > 0),

    CONSTRAINT savings_current_non_negative
        CHECK (current_amount >= 0)

);


/*
===============================================================================
STEP 10: SAVINGS CONTRIBUTIONS
===============================================================================
*/

CREATE TABLE IF NOT EXISTS savings_contributions (

    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    savings_goal_id UUID NOT NULL
        REFERENCES savings_goals(id)
        ON DELETE RESTRICT,

    account_id UUID
        REFERENCES accounts(id)
        ON DELETE RESTRICT,

    transaction_id UUID
        REFERENCES transactions(id)
        ON DELETE SET NULL,

    amount NUMERIC(14,2) NOT NULL,

    contribution_date DATE NOT NULL,

    remarks TEXT,

    created_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT savings_contribution_positive
        CHECK (amount > 0)

);


/*
===============================================================================
STEP 11: FINANCIAL SNAPSHOTS
===============================================================================
*/

CREATE TABLE IF NOT EXISTS financial_snapshots (

    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    snapshot_date DATE NOT NULL,

    total_assets NUMERIC(14,2)
        NOT NULL DEFAULT 0,

    total_liabilities NUMERIC(14,2)
        NOT NULL DEFAULT 0,

    net_worth NUMERIC(14,2)
        GENERATED ALWAYS AS (
            total_assets - total_liabilities
        ) STORED,

    total_income NUMERIC(14,2)
        NOT NULL DEFAULT 0,

    total_expenses NUMERIC(14,2)
        NOT NULL DEFAULT 0,

    total_debt_payment NUMERIC(14,2)
        NOT NULL DEFAULT 0,

    total_savings NUMERIC(14,2)
        NOT NULL DEFAULT 0,

    remarks TEXT,

    created_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_snapshot_date
        UNIQUE (snapshot_date)

);


/*
===============================================================================
STEP 12: INDEXES
===============================================================================
*/

CREATE INDEX IF NOT EXISTS idx_transactions_account
ON transactions(account_id);

CREATE INDEX IF NOT EXISTS idx_transactions_category
ON transactions(category_id);

CREATE INDEX IF NOT EXISTS idx_transactions_date
ON transactions(transaction_date);

CREATE INDEX IF NOT EXISTS idx_transactions_type
ON transactions(transaction_type);

CREATE INDEX IF NOT EXISTS idx_transactions_hash
ON transactions(external_hash);

CREATE INDEX IF NOT EXISTS idx_loans_status
ON loans(status);

CREATE INDEX IF NOT EXISTS idx_loans_next_payment
ON loans(next_payment_date);

CREATE INDEX IF NOT EXISTS idx_loan_payments_loan
ON loan_payments(loan_id);

CREATE INDEX IF NOT EXISTS idx_loan_payments_date
ON loan_payments(payment_date);

CREATE INDEX IF NOT EXISTS idx_savings_goal
ON savings_contributions(savings_goal_id);

CREATE INDEX IF NOT EXISTS idx_savings_date
ON savings_contributions(contribution_date);


/*
===============================================================================
STEP 13: SEED TOP-LEVEL CATEGORIES
===============================================================================
*/

INSERT INTO categories
    (name, type, description)

VALUES
    (
        'Needs',
        'EXPENSE',
        'Essential expenses required for normal living.'
    ),

    (
        'Wants',
        'EXPENSE',
        'Discretionary expenses that can be reduced.'
    ),

    (
        'Financial',
        'EXPENSE',
        'Debt payments, savings, and investments.'
    )

ON CONFLICT DO NOTHING;


/*
===============================================================================
STEP 14: SEED NEEDS CATEGORIES
===============================================================================
*/

INSERT INTO categories
    (name, type, parent_id, description)

SELECT
    v.name,
    'EXPENSE',
    parent.id,
    v.description

FROM (
    VALUES
        ('Rent', 'Housing expense.'),
        ('Groceries', 'Food and household essentials.'),
        ('Electricity', 'Electricity and utility bills.'),
        ('Internet', 'Internet and communication expenses.'),
        ('Transportation', 'Public transportation and travel.'),
        ('Fuel', 'Petrol, diesel, or vehicle charging.'),
        ('Healthcare', 'Medical and health expenses.')
) AS v(name, description)

JOIN categories parent
    ON parent.name = 'Needs'
    AND parent.parent_id IS NULL

ON CONFLICT DO NOTHING;


/*
===============================================================================
STEP 15: SEED WANTS CATEGORIES
===============================================================================
*/

INSERT INTO categories
    (name, type, parent_id, description)

SELECT
    v.name,
    'EXPENSE',
    parent.id,
    v.description

FROM (
    VALUES
        ('Restaurants', 'Eating out and food delivery.'),
        ('Entertainment', 'Movies, games, events, and leisure.'),
        ('Shopping', 'Non-essential shopping.'),
        ('Subscriptions', 'Digital and recurring subscriptions.'),
        ('Gifts', 'Gifts and personal contributions.')
) AS v(name, description)

JOIN categories parent
    ON parent.name = 'Wants'
    AND parent.parent_id IS NULL

ON CONFLICT DO NOTHING;


/*
===============================================================================
STEP 16: SEED FINANCIAL CATEGORIES
===============================================================================
*/

INSERT INTO categories
    (name, type, parent_id, description)

SELECT
    v.name,
    'EXPENSE',
    parent.id,
    v.description

FROM (
    VALUES
        ('Loan EMI', 'Regular scheduled loan payments.'),
        ('Extra Loan Payment', 'Additional payment to reduce debt faster.'),
        ('Savings', 'Money allocated toward savings goals.'),
        ('Investment', 'Money allocated toward investments.')
) AS v(name, description)

JOIN categories parent
    ON parent.name = 'Financial'
    AND parent.parent_id IS NULL

ON CONFLICT DO NOTHING;


/*
===============================================================================
STEP 17: SEED INCOME CATEGORIES
===============================================================================
*/

INSERT INTO categories
    (name, type, description)

VALUES
    (
        'Salary',
        'INCOME',
        'Regular employment income.'
    ),

    (
        'Freelance',
        'INCOME',
        'Freelance and side project income.'
    ),

    (
        'Business Income',
        'INCOME',
        'Income from business activities.'
    ),

    (
        'Bonus',
        'INCOME',
        'Performance bonuses and one-time income.'
    ),

    (
        'Interest Income',
        'INCOME',
        'Interest received from bank deposits or investments.'
    ),

    (
        'Other Income',
        'INCOME',
        'Other income.'
    )

ON CONFLICT DO NOTHING;


/*
===============================================================================
STEP 18: ACCOUNT BALANCE VIEW
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
STEP 19: MONTHLY CASHFLOW VIEW
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
STEP 20: BUDGET VS ACTUAL VIEW
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

        WHEN b.budget_amount = 0
            THEN 0

        ELSE ROUND(

            (
                COALESCE(
                    SUM(t.amount),
                    0
                )

                /

                b.budget_amount

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

    AND t.transaction_date
        < b.month + INTERVAL '1 month'

GROUP BY

    b.id,

    b.month,

    c.name,

    b.budget_amount;


/*
===============================================================================
STEP 21: LOAN SUMMARY VIEW
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
STEP 22: TOTAL DEBT VIEW
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
STEP 23: SAVINGS GOAL PROGRESS VIEW
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
STEP 24: SETUP COMPLETE
===============================================================================

Run these queries to verify the installation.
===============================================================================
*/

SELECT 'Personal Finance Database Setup Completed Successfully!' AS status;

SELECT
    'accounts' AS table_name,
    COUNT(*) AS records
FROM accounts

UNION ALL

SELECT
    'categories',
    COUNT(*)
FROM categories

UNION ALL

SELECT
    'transactions',
    COUNT(*)
FROM transactions

UNION ALL

SELECT
    'budgets',
    COUNT(*)
FROM budgets

UNION ALL

SELECT
    'loans',
    COUNT(*)
FROM loans

UNION ALL

SELECT
    'loan_payments',
    COUNT(*)
FROM loan_payments

UNION ALL

SELECT
    'savings_goals',
    COUNT(*)
FROM savings_goals

UNION ALL

SELECT
    'savings_contributions',
    COUNT(*)
FROM savings_contributions;


/*
===============================================================================
END
===============================================================================
*/

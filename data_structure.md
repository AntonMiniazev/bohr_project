# Report
## Metrics
1. Sales = [fct_orders_sales].[total_amount]
2. Cost of sales = [total_cost] of all products in the order
3. Gross profit (GP): Sales - Cost of sales - tariff

## Filters
Filters should affect all visuals where applicable
1. Range of dates by order_date
2. Store name
3. Zone name

## Visuals in the report:
1. Total sales and total orders by month with drill to days: maybe bar+line chart with period data at X-axis and Sales amount/Orders count at Y-axis and line with average order amount.
2. Top performing stores: table with columns 'Store name', 'Average order value, $', 'Total sales, $', 'Total GP, $'

# Data marts:
- [Ampere].[reporting].[dim_clients]
    - [client_id]
    - [fullname]
    - [preferred_store_id]
    - [registration_date]

- [Ampere].[reporting].[fct_orders_sales]
    - [order_id]
    - [client_id]
    - [order_date]
    - [order_source_id]
    - [total_amount]

- [Ampere].[reporting].[dim_delivery_cost]
    - [order_id]
    - [tariff]

- [Ampere].[reporting].[dim_costing]
    - [order_id]
    - [product_id]
    - [quantity]
    - [store_id]
    - [avg_cost]
    - [total_cost]

- [Ampere].[reporting].[dim_stores]
    - [store_id]
    - [city]
    - [store_name]
    - [zone_name]

# Color pallete
{

/*Heads*/
--prussian-blue: #002642ff;
--claret: #840032ff;
--orange-web: #ffb01fff;
--silver: #b8b7b7ff;
--rich-black: #02040fff;
--brown: #944710ff;
/* Elements */
--cerulean: #2d728fff;
--blue-munsell: #18B6EB;
--vanilla: #f5ee9eff;
--sandy-brown: #996371;
--fire-brick: #EB134B;

}
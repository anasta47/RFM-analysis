with orders_date as (
	select 
		card, 
		datetime::date as order_date,
		max(datetime::date) over () - datetime::date as diff, -- дата последней записи в БД - дата заказа
		row_number() over (partition by card) as rn
	from bonuscheques b
	where card like '200%' --берем данные карт, когда касса была в онлайн режиме
	order by card, datetime desc 
),
recency as (
		select card, order_date, diff, rn
		from orders_date od
		where rn = 1
		),
rfm as (
	select b.card, 
		   count(distinct doc_id) as frequency,  -- считаем по чекам
		   sum(summ) as monetary,
		   max(r.diff) as recency
	from bonuscheques b
	join recency r
	on r.card = b.card
	where b.card like '200%'
	group by b.card
	having count(distinct doc_id) > 1 -- отсеиваем "случайных" покупателей, чтобы сконцентрироваться на более потенциальных
),
perc as (
-- находим 33й и 66й перцентиль, чтобы разделить группы на равные части
	select 
	   percentile_cont(0.33) WITHIN GROUP (ORDER BY recency) as per_recency1,
	   percentile_cont(0.66) WITHIN GROUP (ORDER BY recency) as per_recency2,
	   percentile_cont(0.33) WITHIN GROUP (ORDER BY frequency desc) as per_frequency1,
	   percentile_cont(0.66) WITHIN GROUP (ORDER BY frequency desc) as per_frequency2,
	   percentile_cont(0.33) WITHIN GROUP (ORDER BY monetary desc) as per_monetary1,
	   percentile_cont(0.66) WITHIN GROUP (ORDER BY monetary desc) as per_monetary2
	from rfm
	),
rfm_groups as (	
 select card, 
		recency,
		case 
			when recency < per_recency1 then '1' -- разделяем клиентов на группы по каждому признаку
			when recency < per_recency2 then '2'
			else '3'
			end as "R",
		frequency,
		case 
			when frequency > per_frequency1 then '1'
			when frequency > per_frequency2 then '2'
			else '3'
		end as "F",
		monetary,
		case 
			when monetary > per_monetary1 then '1'
			when monetary > per_monetary2 then '2'
			else '3'
		end as "M"
	from rfm, perc p 
	),
rfm_common as (
 select card as client,
 		recency,
		frequency,
		monetary,
	    concat("R","F","M") as "RFM"
from rfm_groups
order by "RFM"
)
select 
		client,
		"RFM",
		-- формируем и называем группы 
		case 
			when "RFM" in ('111') then 'VIP клиенты'
			when "RFM" in ('112', '121', '122') then 'Лояльные постоянные'
			when "RFM" in ('113', '213') then 'Постоянные с небольшим бюджетом'
			when "RFM" in ('221', '122', '123', '131', '212', '231') then 'Потенциальные'
			when "RFM" in ('312', '313', '321', '322') then 'Спящие потенциальные'
			when "RFM" in ('133', '132', '222', '223', '232', '233') then 'Низкопотенциальные'
			when "RFM" in ('211', '311') then 'Потерянные VIP'
			else 'Спящие низкопотенциальные'
		end as "Название группы"
from rfm_common



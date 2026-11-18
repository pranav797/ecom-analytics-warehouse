-- Generic test: fails on every row where `expression` is false.
-- Usage in YAML:  - expression_is_true: {arguments: {expression: "price >= 0"}}
{% test expression_is_true(model, expression, column_name=None) %}
select * from {{ model }} where not ({{ expression }})
{% endtest %}

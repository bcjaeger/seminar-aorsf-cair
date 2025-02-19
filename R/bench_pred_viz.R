perc_diff <- function(a,b){
 100 * (a-b) / b
}


viz_surv_bm <- function(
  model_subset = NULL,
  eval_metric = 'ibs_scaled'
){

 bm_pred_clean <- read_rds(
  'data/bm_pred_clean.rds'
 )

 model_key <- read_rds(
  "data/model_key.rds"
 ) %>%
  mutate(
   label = recode(
    label,
    'obliqueRSF-net' = 'obliqueRSF',
    'aorsf-fast' = 'aorsf',
    'xgboost-cox' = 'xgboost',
    'glmnet-cox' = 'glmnet',
    'rsf-standard' = 'randomForestSRC',
    'ranger-extratrees' = 'ranger',
    'cif-standard' = 'party',
    'nn-cox' = 'neural network'
   )
  )

 data_key <- read_rds(
  "data/data_key.rds"
 )

 fig_subsets <- list(
  slide_one = c('obliqueRSF',
                'randomForestSRC',
                'ranger',
                'party'),
  slide_two = c('obliqueRSF',
                'aorsf',
                'randomForestSRC',
                'ranger',
                'party')
 )

 data_recoder <- data_key %>%
  transmute(data, label = paste(label, outcome, sep = '; ')) %>%
  deframe()

 model_recoder <- deframe(model_key)

 switch (

  eval_metric,

  'ibs_scaled' = {

   y_col_1 <- -0.4
   y_min <- 0
   y_breaks <- seq(0, .6, by = .1)
   eval_label <- 'Index of Prediction Accuracy'

  },

  'cstat' = {

   y_col_1 <- 0.35
   y_min <- .55
   y_breaks <- seq(.7, 1, by = .1)
   eval_label <- 'C-statistic'

  }

 )

 bm_pred_inner <- bm_pred_clean %>%
  rename(eval = .data[[eval_metric]])

 if(eval_metric == 'ibs_scaled'){
  bm_pred_inner <- bm_pred_inner %>%
   filter(model != 'xgb_aft') %>%
   droplevels()
 }

 data_smry_overall <- bm_pred_inner %>%
  mutate(data = fct_reorder(factor(data), .x = eval)) %>%
  group_by(model) %>%
  summarize(eval = mean(eval)) %>%
  mutate(data = 'Overall')

 data_levels <- c(
  "Overall",
  levels(
   with(
    bm_pred_inner,
    fct_reorder( factor(data),  .x = eval )
   )
  )
 )

 data_smry <- bm_pred_inner %>%
  group_by(model, data) %>%
  summarize(eval = mean(eval)) %>%
  bind_rows(data_smry_overall) %>%
  mutate(data = factor(data, levels = data_levels)) %>%
  arrange(data, desc(eval)) %>%
  mutate(x = as.numeric(fct_rev(data)),
         data = recode(data, !!!data_recoder)) %>%
  select(model, data, x, eval) %>%
  group_by(data) %>%
  mutate(x = x + seq(-1/3, 1/3, length.out = n()))

 gg_text_data <- data_smry %>%
  group_by(data) %>%
  summarize(x = median(x)) %>%
  mutate(eval = y_col_1)

 data_aorsf <- data_smry %>%
  filter(model == 'aorsf_fast')

 aorsf_wins <- data_smry %>%
  filter(model != 'aorsf_cph',
         model != 'aorsf_fast_filter',
         model != 'aorsf_net',
         model != 'obliqueRSF') %>%
  arrange(data, desc(eval)) %>%
  mutate(rank = seq(n())) %>%
  filter(rank == 1 & model == 'aorsf_fast') %>%
  pull(data)

 rankings <- data_smry %>%
  filter(model != 'aorsf_cph',
         model != 'aorsf_fast_filter',
         model != 'aorsf_net',
         model != 'obliqueRSF') %>%
  arrange(data, desc(eval)) %>%
  mutate(rank = seq(n()))

 avg_ranking <- rankings %>%
  filter(data != 'Overall') %>%
  group_by(model) %>%
  summarize(rank_median = median(rank),
            rank_mean = mean(rank),
            n_wins = sum(rank == 1))

 gg_text_diffs <- rankings %>%
  filter(data %in% aorsf_wins, rank <= 2) %>%
  group_split() %>%
  map_dfr(
   .f = ~{

    tibble(data = .x$data[1],
           pdiff = perc_diff(.x$eval[1], .x$eval[2]),
           adiff = diff(rev(.x$eval)))

   }
  ) %>%
  left_join(gg_text_data) %>%
  mutate(
   eval = map_dbl(
    data,
    ~data_aorsf %>%
     filter(data == .x) %>%
     pull(eval)
   ),
   label = table_glue("+{100*adiff} ({pdiff}%)")
  )

 data_fig <- data_smry %>%
  filter(!str_detect(model, '^aorsf|obliqueRSF$')) %>%
  droplevels()

 model_levels <- data_fig %>%
  filter(data == 'Overall') %>%
  arrange(eval) %>%
  pull(model) %>%
  as.character() %>%
  c('aorsf_fast')

 data_fig <- data_fig %>%
  filter(eval > y_min)

 oranges <-
  RColorBrewer::brewer.pal(n = length(model_levels) - 1, "Oranges")
 standout <- "purple"


 gg_legend <- ggpubr::get_legend(
  data_fig %>%
   bind_rows(data_aorsf) %>%
   mutate(model = factor(model,
                         levels = model_levels,
                         labels = model_recoder[model_levels])) %>%
   ggplot(aes(x=x, y=eval, col=model)) +
   geom_point() +
   scale_color_manual(values = c(oranges, standout)) +
   theme_bw() +
   theme(legend.position = 'top') +
   labs(color = '') +
   guides(colour = guide_legend(nrow = 2,
                                override.aes = list(size=8)))
 )

 data_fig$model <- factor(
  data_fig$model,
  levels = setdiff(model_levels, 'aorsf_fast')
 )

 xmax <- max(data_fig$x)

 gg_text_header <- tibble(
  x = c(xmax + 3/4, xmax + 3/4),
  eval = c(y_col_1, (min(y_breaks) + max(y_breaks)) / 2),
  label = c("Dataset; outcome", eval_label),
  hjust = c(0, 1/2)
 )

 gg_rect <- tibble(
  xmin = seq(xmax+1) - 1/2,
  xmax = seq(xmax+1) + 1/2,
  ymin = -Inf,
  ymax = Inf
 ) %>%
  filter(seq(n()) %% 2 == 0)

 gg_fig <- ggplot(data_fig) +
  aes(x = x, y = eval) +
  geom_point(shape = 21,
             size = 2,
             aes(fill = model)) +
  geom_point(data = data_aorsf,
             shape = 21,
             size = 3,
             fill = standout) +
  geom_text(data = gg_text_data,
            aes(label = data),
            hjust = 0) +
  geom_text(data = gg_text_diffs,
            aes(label = label),
            hjust = -0.2,
            color = standout) +
  geom_text(data = gg_text_header,
            aes(label = label,
                hjust = hjust)) +
  coord_flip() +
  theme_bw() +
  theme(panel.grid = element_blank(),
        panel.border = element_blank(),
        axis.ticks.y = element_blank(),
        axis.text.y = element_blank(),
        legend.position = '') +
  scale_fill_manual(values = oranges) +
  scale_y_continuous(limits = c(y_col_1, max(data_fig$eval)*1.15),
                     expand = c(0, 0),
                     breaks = y_breaks,
                     labels = function(x) x * 100) +
  scale_x_continuous(limits = c(0, xmax + 2),
                     expand = c(0, 0)) +
  geom_segment(x = 0, xend = 0,
               y = 0, yend = max(y_breaks)) +
  geom_rect(data = gg_rect,
            inherit.aes = FALSE,
            aes(xmin = xmin,
                xmax = xmax,
                ymin = ymin,
                ymax = ymax),
            fill = 'grey',
            alpha = 1/6) +
  labs(x = '', y = '')

 fig <- cowplot::plot_grid(
  gg_legend,
  gg_fig,
  nrow = 2,
  rel_heights = c(0.075, 0.935)
 )

 list(
  smry = data_smry,
  diffs = gg_text_diffs,
  rankings = avg_ranking,
  fig = fig
 )



}

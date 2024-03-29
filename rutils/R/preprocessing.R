library(tidyverse)
library(HDF5Array)

figo_map_df <- tibble(
    roman_num = c("I", "II", "III", "IV"),
    figo_chr = c('figo_stage_1', 'figo_stage_2', 'figo_stage_3', 'figo_stage_4'),
    figo_num = c(1, 2, 3, 4)
)

load_matrisome_df <- function(matrisome_list_file) {
    matrisome_df <- readr::read_tsv(matrisome_list_file, quote = "")
    colnames(matrisome_df) <- purrr::map(sub(" ", "_", colnames(matrisome_df)), tolower)
    matrisome_df <- dplyr::select(matrisome_df, gene_symbol, everything()) %>%
        dplyr::filter(division != "Retired")    # Ignore "Retired" matrisome genes
    return(matrisome_df)
}


load_survival_df <- function(survival_data_file, event_code) {
    survival_df <- read_tsv(survival_data_file) %>%
        mutate(vital_status_num = case_when(
            vital_status == "Dead" ~ event_code[["Dead"]],
            vital_status == "Alive" ~ event_code[["Alive"]]
        )) %>%
        dplyr::select(sample_name, vital_status_num, everything(), -vital_status) %>%
        dplyr::rename(vital_status = vital_status_num)
    return(survival_df)
}


load_and_combine_count_matrix_data <- function(count_files, coldata_files, count_join_symbols) {
    count_df_ls <- purrr::map(.x = count_files, .f = readr::read_tsv)
    coldata_df_ls <- purrr::map(.x = coldata_files, .f = readr::read_tsv)

    coldata_df <- dplyr::bind_rows(coldata_df_ls)
    count_df <- purrr::reduce(count_df_ls, dplyr::inner_join, by = count_join_symbols)
    return(list(counts_df = count_df, coldata_df = coldata_df))
}


balanced_group_sample <- function(counts, coldata, centroids, groups, n, group_col, sample_col) {
    samples <- list()
    for (group in groups) {
        group_mask <- coldata[[group_col]] == group
        group_counts <- counts[, coldata[[sample_col]][group_mask]]
        centroid <- centroids[[group]]
        res <- find_n_closest(group_counts, centroid, n, sample_col) %>%
            mutate("group" = group)
        samples[[group]] <- res
    }
    return(bind_rows(samples) %>% dplyr::arrange_at(sample_col))
}


get_hm_dfs <- function(counts_df, coldata_df, hm_sample_meta_df, drop_low_sd = TRUE, eps = 1e-6) {
    hm_sample_counts_df <- counts_df[, c("external_gene_name", hm_sample_meta_df$sample_name)] %>%
        column_to_rownames(var = "external_gene_name")
    hm_sample_coldata_df <- coldata_df %>%
        dplyr::filter(sample_name %in% hm_sample_meta_df$sample_name) %>%
        arrange(match(sample_name, hm_sample_meta_df$sample_name)) %>%
        column_to_rownames(var = "sample_name") # Heatmap needs row names

    if (drop_low_sd) {
        gene_sd_mask <- rowSds(as.matrix(hm_sample_counts_df)) > eps
        hm_sample_counts_df <- hm_sample_counts_df[gene_sd_mask, ]
    }

    hm_sample_ls <- list(
        coldata = hm_sample_coldata_df,
        counts = hm_sample_counts_df
    )
    stopifnot(all(colnames(hm_sample_counts_df) == rownames(hm_sample_coldata_df)))
    return(hm_sample_ls)
}


get_hm_clusters <- function(counts_df, col_cor = "spearman", row_cor = "pearson", col_metric = "complete", row_metric = "complete") {
    col_dist <- as.dist(1 - cor(as.matrix(counts_df), method = col_cor))
    row_dist <- as.dist(1 - cor(t(as.matrix(counts_df)), method = row_cor))

    return(list(
        col = hclust(col_dist, method = col_metric),
        row = hclust(row_dist, method = row_metric)
    ))
}


load_RSE_objects <- function(dir, projects, prefixes) {
    data_ls <- list()
    for (i in seq_len(length(projects))) {
        data_ls[[projects[i]]] <- loadHDF5SummarizedExperiment(dir = dir, prefix = prefixes[i])
    }
    return(data_ls)
}


to_one_hot <- function(df, col) {
    one_hot <- model.matrix(
        as.formula(paste0("~ ", col, " - 1")),    # We do not want the intercept
        model.frame(~ ., df[col], na.action = na.pass)
    )
    # Don't want white space
    colnames(one_hot) <- gsub(" ", "_", colnames(one_hot))
    # model.matrix() will prepend original column name to each one-hot column
    colnames(one_hot) <- gsub(col, paste0(col, "_"), colnames(one_hot))
    return(tibble::as_tibble(one_hot))
}


decode_figo_stage <- function(df, to = "num") {
    if (str_sub(to, 1, 1) == "n") {
        drop_col <- "figo_chr"
        keep_col <- "figo_num"
    }
    else if (str_sub(to, 1, 1) == "c") {
        drop_col <- "figo_num"
        keep_col <- "figo_chr"
    }

    new_df <- df %>%
        dplyr::mutate(
            figo_rn = str_extract(figo_stage, "IV|III|II|I")
        ) %>%
        dplyr::inner_join(figo_map_df, by = c("figo_rn" = "roman_num")) %>%
        dplyr::select(-c("figo_rn", "figo_stage", drop_col)) %>%
        dplyr::rename("figo_stage" = keep_col)
    return(new_df)
}


get_unified_group_samples <- function(counts_df, coldata_df, sample_group) {
    if (sample_group == "GTEX") {
        group_samples <- (coldata_df %>%
            dplyr::filter(data_source == "GTEx"))$sample_name
    }
    else if (sample_group == "TCGA_healthy") {
        group_samples <- (coldata_df %>%
            dplyr::filter(condition == "healthy" & data_source == "TCGA"))$sample_name
    }
    else if (sample_group == "TCGA_tumor") {
        group_samples <- (coldata_df %>%
            dplyr::filter(condition == "tumor"))$sample_name
    }
    
    return(counts_df %>% dplyr::select("geneID", all_of(group_samples)))
}


get_unified_thresh_results <- function(group_df, thresh, group_name) {
    over_thresh_str <- paste0(group_name, "_over_thresh")
    over_thresh_prop_str <- paste0(group_name, "_over_thresh_prop")

    res_df <- group_df %>%
        mutate(over_thresh = rowSums(. [, -1] > thresh)) %>%
        mutate(over_thresh_prop = over_thresh / (ncol(.) - 2)) %>%
        dplyr::rename(!!over_thresh_str := over_thresh) %>%
        dplyr::rename(!!over_thresh_prop_str := over_thresh_prop) %>%
        dplyr::select(matches(c("geneID", over_thresh_str, over_thresh_prop_str)))
    return(res_df)
}


get_unified_thresh_results_for_all <- function(counts_df, coldata_df, group_names, thresh) {
    df_list <- list()
    for (gn in group_names) {
        group_counts_df <- get_unified_group_samples(counts_df, coldata_df, gn)
        thresh_res_df <- get_unified_thresh_results(group_counts_df, thresh, gn)
        df_list[[gn]] <- thresh_res_df
    }
    final_df <- df_list %>%
        purrr::reduce(inner_join, by = "geneID") %>%
        mutate(
            tot_over_thresh = rowSums(select(., paste0(group_names, "_over_thresh"))),
            tot_over_thresh_prop = tot_over_thresh / (ncol(counts_df) - 1)    # subtract 1 because we assume gene names is a column
        )
    return(final_df)
}


transpose_df <- function(df, future_colnames_col, previous_colnames_col) {
    temp_df <- as.data.frame(df)
    rownames(temp_df) <- df[[future_colnames_col]]
    temp_df <- temp_df %>% dplyr::select(-(!!future_colnames_col))
    t(temp_df) %>% as_tibble(rownames = previous_colnames_col)
}


filter_outliers_IQR <- function(df, filter_col, coef) {
    quantiles <- quantile(df[[filter_col]])
    q_1 <- quantiles[2]
    q_3 <- quantiles[4]
    iqr <- q_3 - q_1
    min_thresh <- q_1 - coef * iqr
    max_thresh <- q_3 + coef * iqr

    filtered_df <- df %>%
        dplyr::mutate(outlier_status = (!!as.name(filter_col) < min_thresh) | (max_thresh < !!as.name(filter_col))) %>%
        dplyr::filter(outlier_status == FALSE) %>%
        dplyr::select(-outlier_status)

    return(filtered_df)
}


select_substring_patterns <- function(df, substrings, complement = FALSE) {
    substring_union <- paste(substrings, collapse = "|")
    condensed_df <- df %>%
        { if (complement) dplyr::select_if(!grepl(substring_union, colnames(.))) else dplyr::select_if(grepl(substring_union, colnames(.))) }
    return(condensed_df)
}


condense_figo <- function(df, include_pvals = TRUE) {
    if (include_pvals) {
        figo_pval_cols <- colnames(df)[grepl("figo_stage_[1-4]_pval", colnames(df))]
    }
    figo_qval_cols <- colnames(df)[grepl("figo_stage_[1-4]_qval", colnames(df))]
    figo_cor_cols <- colnames(df)[grepl("figo_stage_[1-4]_cor", colnames(df))]

    filtered_df <- df %>%
        { if (include_pvals) dplyr::mutate(., figo_min_pval = apply(df[figo_pval_cols], MARGIN = 1, FUN = min)) else . } %>%
        dplyr::mutate(figo_min_qval = apply(df[figo_qval_cols], MARGIN = 1, FUN = min)) %>%
        dplyr::mutate(figo_max_cor = apply(df[figo_cor_cols], MARGIN = 1, FUN = max)) %>%
        dplyr::select(-matches("figo_stage_[0-9]")) %>%
        { if (!include_pvals) dplyr::select(., -vital_pval) else .}
    return(filtered_df)
}


make_ea_df <- function(res, ea_type) {
    lc_ea_type <- tolower(ea_type)
    if (lc_ea_type == "go") {
        df <- tibble(
            type = res$Description,
            geneIDs = res$geneID,
            count = res$Count,
            ratio = sapply(res$GeneRatio, FUN = function(x) { eval(parse(text = x)) }),
            qval = res$qvalue,
            ont = as.character(res$ONTOLOGY)
        )
    } else if (lc_ea_type == "kegg") {
        df <- tibble(
            type = res$Description,
            geneIDs = res$geneID,
            count = res$Count,
            ratio = sapply(res$GeneRatio, FUN = function(x) { eval(parse(text = x)) }),
            qval = res$qvalue
        )
    }
    return(df)
}


deg_meta <- function(df, lfc_thresh, q_thresh, n) {
    deg_df <- df %>%
        dplyr::filter(abs(lfc) > lfc_thresh, qval < q_thresh)
    list(
        n_deg = nrow(deg_df),
        deg_prop = nrow(deg_df) / n,
        n_up = nrow(deg_df %>% dplyr::filter(lfc > 0)),
        n_down = nrow(deg_df %>% dplyr::filter(lfc < 0)),
        genes = deg_df$geneID
    )
}


mi_meta <- function(df, pct_max_thresh) {
    ord_df <- df %>%
        dplyr::arrange(desc(mi_est)) %>%
        dplyr::mutate(pct_max = mi_est / first(mi_est) * 100) %>%
        dplyr::filter(pct_max > pct_max_thresh)
    list(
        n_mi = nrow(ord_df),
        genes = ord_df$geneID
    )
}


lr_l1_meta <- function(score_df, res_df, baseline_df) {
    consensus_genes <- res_df %>%
        dplyr::filter(consensus == TRUE) %>%
        pull(geneID)
    avg_score <- mean(score_df$ref_score)
    naive_pct_imp <- (avg_score - baseline_df$naive) / baseline_df$naive * 100
    mc_pct_imp <- (avg_score - baseline_df$mc) / baseline_df$mc * 100
    list(
        avg_score = avg_score,
        naive_pct_imp = naive_pct_imp,
        mc_pct_imp = mc_pct_imp,
        n_genes = length(consensus_genes),
        genes = consensus_genes
    )
}

wgcna_meta <- function(me_df, mm_df, q_me_thresh, p_mm_thresh, keeper_genes) {
    condensed_me_df <- me_df %>%
        condense_figo(include_pvals = TRUE) %>%
        dplyr::rename_if(!startsWith(colnames(.), "module"), ~ gsub("^", "me_", .))
    filtered_network_df <- mm_df %>%
        dplyr::select(geneID, module, mm_pval, mm_cor) %>%
        inner_join(condensed_me_df, by = "module") %>%
        dplyr::filter(me_figo_min_qval < q_me_thresh) %>%
        # Make sure genes are significant members of the module
        dplyr::filter(mm_pval < p_mm_thresh) %>%
        # Make sure genes are highly connected within the module
        dplyr::filter(geneID %in% keeper_genes)
    list(
        n_sig_modules = length(unique(filtered_network_df$module)),
        n_sig_genes = nrow(filtered_network_df),
        modules = unique(filtered_network_df$module),
        genes = filtered_network_df$geneID
    )
}

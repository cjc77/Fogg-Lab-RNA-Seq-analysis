import pandas as pd
import numpy as np
import os
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import cross_val_score, KFold
from sklearn.metrics import f1_score
from skopt.space import Real, Integer, Categorical
from skopt import gp_minimize

import utils.dev_config as dev_conf
import utils.preprocessing as prep
import utils.optimization as opt


# Helper functions
def objective(h_params, X, y, loss_default, scoring_default, r, verbose=True):
    if verbose:
        print(h_params)
    model = GradientBoostingClassifier(
        loss=loss_default,
        learning_rate=h_params[0],
        n_estimators=h_params[1],
        max_depth=h_params[2],
        max_features=h_params[3],
        min_samples_split=h_params[4],
        min_samples_leaf=h_params[5],
        random_state=r
    )
    return -np.mean(cross_val_score(model, X, y, cv=KFold(n_splits=5), n_jobs=-1, scoring=scoring_default))


def run_optimization(x_df, y_df, space, loss_default, scoring_default, rand, n_initial, n_calls, callback_file):
    try:
        os.remove(callback_file)
    except OSError:
        pass

    res = gp_minimize(
        lambda h_ps: objective(h_ps, x_df, y_df.values.squeeze(), loss_default, scoring_default, rand),
        space,
        verbose=True,
        random_state=rand,
        n_initial_points=n_initial,
        n_calls = n_calls,
        n_jobs=-1,
        callback=lambda x: opt.save_callback(x, callback_file, n = 5, sep="\t")
    )


# Define constants
dirs = dev_conf.get_dev_directories("../dev_paths.txt")
unified_dsets = ["unified_cervical_data", "unified_uterine_data", "unified_uterine_endometrial_data"]
seed = 123
rand = np.random.RandomState()
event_code = {"Alive": 0, "Dead": 1}
covariate_cols = ["age_at_diagnosis", "race", "ethnicity"]
dep_cols = ["figo_stage"]
cat_cols = ["race", "ethnicity"]
space = [
    Real(1e-3, 1e-1, name="learning_rate"),
    Integer(int(1e2), int(1e3), name="n_estimators"),
    Integer(2, 5, name="max_depth"),
    Categorical(["auto", "sqrt", "log2"], name="max_features"),
    Integer(int(2), int(6), name="min_samples_split"),
    Integer(int(1), int(3), name="min_samples_leaf")
]
n_initial = 10 * len(space)
n_calls = 50 * len(space)

scoring_method = "f1_macro"


def main():
    # Train models
    for dset_idx in range(3):
        # Load and filter survival data
        survival_df = prep.load_survival_df(f"{dirs.data_dir}/{unified_dsets[dset_idx]}/survival_data.tsv", event_code)
        filtered_survival_df = (
            prep.decode_figo_stage(survival_df[["sample_name"] + dep_cols + covariate_cols].dropna(), to="n")
                .pipe(pd.get_dummies, columns=cat_cols)
                .reset_index(drop = True)
                .pipe(prep.cols_to_front, ["sample_name", "figo_num"])
        )
        filtered_survival_df.columns = filtered_survival_df.columns.str.replace(' ', '_')

        # Load normalized matrisome count data
        norm_matrisome_counts_df = pd.read_csv(f"{dirs.data_dir}/{unified_dsets[dset_idx]}/norm_matrisome_counts.tsv", sep='\t')
        norm_filtered_matrisome_counts_t_df = prep.transpose_df(
            norm_matrisome_counts_df[["geneID"] + list(filtered_survival_df.sample_name)], "geneID", "sample_name"
        )

        # Combine survival data and normalized count data
        joined_df = (
            pd.merge(filtered_survival_df, norm_filtered_matrisome_counts_t_df, on="sample_name")
                .set_index("sample_name")
        )

        # Ignore covariates
        matrisome_genes = list(norm_filtered_matrisome_counts_t_df.columns[1:])
        joined_df = joined_df[["figo_num"] + matrisome_genes]

        rand.seed(seed)
        x_df, y_df = prep.shuffle_data(joined_df, rand)

        # Optimize models
        run_optimization(
            x_df, y_df, space, "deviance", scoring_method, rand, n_initial, n_calls,
            f"{dirs.analysis_dir}/model_opt/{unified_dsets[dset_idx]}_opt_gbc_h_params_{scoring_method}.tsv"
        )

        print(f"Completed dataset: {unified_dsets[dset_idx]}")


if __name__ == "__main__":
    main()

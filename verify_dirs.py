import os
import sys


all_present = True
cervical_dir = "unified_cervical_data"
matrisome_dir = "matrisome"
cancer_dsets = ["unified_cervical_data", "unified_uterine_data", "unified_uterine_endometrial_data"]


dev_paths_file = "dev_paths.txt"
counts_file = "counts.tsv"
coldata_file = "coldata.tsv"
matrisome_masterlist_file = "matrisome_hs_masterlist.tsv"


# Check existence of dev_paths_file
if not os.path.exists(dev_paths_file):
    print(f"[FAILURE] Could not find: {dev_paths_file}")
    print(f"You must create this file with the specifications listed in README.md.")
    sys.exit("Please create this file and try again.")
else:
    print(f"[SUCCESS] Found: {dev_paths_file}")

with open("dev_paths.txt") as f:
    dirs = tuple(fn.strip() for fn in f.readlines())
    data_dir, analysis_dir, figures_dir = dirs

# Check existence of cancer data
for dset in cancer_dsets:
    if not os.path.exists(f"{data_dir}/{dset}/{coldata_file}"):
        print(f"[FAILURE] Could not find: {data_dir}/{dset}/{coldata_file}")
        all_present = False
    else:
        print(f"[SUCCESS] Found: {data_dir}/{dset}/{coldata_file}")

    if not os.path.exists(f"{data_dir}/{dset}/{counts_file}"):
        print(f"[FAILURE] Could not find: {data_dir}/{dset}/{counts_file}")
        all_present = False
    else:
        print(f"[SUCCESS] Found: {data_dir}/{dset}/{counts_file}")


# Check existence of matrisome data
if not os.path.exists(f"{data_dir}/{matrisome_dir}/{matrisome_masterlist_file}"):
    print(f"[FAILURE] Could not find: {data_dir}/{matrisome_dir}/{matrisome_masterlist_file}")
    all_present = False
else:
    print(f"[SUCCESS] Found: {data_dir}/{matrisome_dir}/{matrisome_masterlist_file}")

# Check existence of analysis directory
if not os.path.exists(analysis_dir):
    os.makedirs(analysis_dir)
    print(f"[SUCCESS] Created analysis directory: {analysis_dir}")
else:
    print(f"[SUCCESS] Analysis directory already exists.")

# Check existence of analysis/meta directory
if not os.path.exists(f"{analysis_dir}/meta"):
    os.makedirs(f"{analysis_dir}/meta")
    print(f"[SUCCESS] Created analysis/meta directory: {analysis_dir}/meta")
else:
    print(f"[SUCCESS] Analysis meta directory already exists.")

# Check existence of analysis/network directory
if not os.path.exists(f"{analysis_dir}/network"):
    os.makedirs(f"{analysis_dir}/network")
    print(f"[SUCCESS] Created analysis/network directory: {analysis_dir}/network")
else:
    print(f"[SUCCESS] Analysis network directory already exists.")

# Check existence of figures directory
if not os.path.exists(figures_dir):
    os.makedirs(figures_dir)
    print(f"[SUCCESS] Created figures directory: {figures_dir}")
else:
    print(f"[SUCCESS] Figures directory already exists.")

# Check existence of figures/network directory
if not os.path.exists(f"{figures_dir}/network"):
    os.makedirs(f"{figures_dir}/network")
    print(f"[SUCCESS] Created figures/network directory: {figures_dir}/network")
else:
    print(f"[SUCCESS] Figures network directory already exists.")

# Check existence of figures/enrichment directory
if not os.path.exists(f"{figures_dir}/enrichment"):
    os.makedirs(f"{figures_dir}/enrichment")
    print(f"[SUCCESS] Created figures/enrichment directory: {figures_dir}/enrichment")
else:
    print(f"[SUCCESS] Figures enrichment directory already exists.")



if all_present:
    print(f"[ALL SUCCEEDED] All necessary data/directories present.")
else:
    print(f"[FAILURES PRESENT] Check messages and make sure all needed directories/files are present.")

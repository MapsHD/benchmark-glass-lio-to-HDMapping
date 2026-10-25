# glass-lio to HDMapping simplified instruction

## Step 1 (prepare data)
Download the dataset `reg-1.bag` by clicking [link](https://cloud.cylab.be/public.php/dav/files/7PgyjbM2CBcakN5/reg-1.bag) or from the [Zenodo](https://zenodo.org/records/23069933) mirror (it is part of [Bunker DVI Dataset](https://charleshamesse.github.io/bunker-dvi-dataset)) and convert with [tool](https://github.com/MapsHD/livox_bag_aggregate) to `reg-1.bag-pc.bag`.

On Zenodo the bag archive is split into `reg-1.zip.part-000`, `reg-1.zip.part-001`, etc.,
download all parts, then merge and extract them:

```bash
cd ~/Downloads
cat reg-1.zip.part-0* > full.zip
zip -F full.zip --out full-fixed.zip
unzip full-fixed.zip
```

File `reg-1.bag-pc.bag` is an input for further calculations.
It should be located in `~/hdmapping-benchmark/data`.

## Step 2 (prepare docker)
```shell
mkdir -p ~/hdmapping-benchmark
cd ~/hdmapping-benchmark
git clone https://github.com/MapsHD/benchmark-glass-lio-to-HDMapping.git --recursive
cd benchmark-glass-lio-to-HDMapping
git checkout Bunker-DVI-Dataset-reg-1
docker build -t glass-lio_humble .
```

## Step 3 (run docker, file `reg-1.bag-pc.bag` should be in `~/hdmapping-benchmark/data`)
```shell
cd ~/hdmapping-benchmark/benchmark-glass-lio-to-HDMapping
chmod +x docker_session_run-ros2-glass-lio.sh
cd ~/hdmapping-benchmark/data
~/hdmapping-benchmark/benchmark-glass-lio-to-HDMapping/docker_session_run-ros2-glass-lio.sh reg-1.bag-pc.bag .
```

While the bag plays you can watch glass-lio build the map live in RViz, before the algorithm diverges:

![glass-lio running in RViz, before the algorithm diverges](images/Rviz.png)

## Step 4 (Open and visualize data)
Expected data should appear in `~/hdmapping-benchmark/data/output_hdmapping-glass-lio`.
Use tool [multi_view_tls_registration_step_2](https://github.com/MapsHD/HDMapping) to open `session.json` from `~/hdmapping-benchmark/data/output_hdmapping-glass-lio`.

![glass-lio session opened in HDMapping multi_view_tls_registration_step_2](images/Step2_1.png)

You can see artifacts after scrolling and rotating:

![glass-lio session artifacts in HDMapping multi_view_tls_registration_step_2, after scrolling and rotating](images/Step2_2.png)

You should see the following data in folder `~/hdmapping-benchmark/data/output_hdmapping-glass-lio`:

lio_initial_poses.reg

poses.reg

scan_lio_*.laz

session.json

trajectory_lio_*.csv

## Contact email
januszbedkowski@gmail.com

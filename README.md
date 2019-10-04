# nemo-multigrid-adaptation
This repository contains sources for a modified version of NEMO 3.6 ocean model adapted for multigrid high-resolution Arctic simulation. These modifications provides more exible and customisable tools for high-resolution regional Arctic (but not restricted to it) simulations, that helps in the assessment of shipping and operational risks.
The details of proposed changes are described in this [paper](https://www.sciencedirect.com/science/article/abs/pii/S1463500318301410).
## More
First of all, we aimed to create a dataset with appropriate historical coverage and sufficiently high spatial resolution. We reached our goals with a custom simulation framework comprising three main components: 
* the WRF atmospheric model
* the WaveWatch III spectral wave model
* the NEMO ocean model, the last one coupled with the LIM3 ice model
A multi-grid model with two connected configurations (coarse-resolution and fine-resolution) was used to obtain output data from coarse-resolution modified model and then to input this data to fine-resolution model.
## Conclusion
Compared to that of the built-in AGRIF nesting system, our configurations show lower resulting computational cost. 
Using the ice-restoring scheme we managed to reduce spin-up time and increase the quality of both coarse- and fine-grid configurations. 
We increased quality of regional ice modelling due to the implementation of the ice drift boundary condition.

How-to-use instructions will be added later.


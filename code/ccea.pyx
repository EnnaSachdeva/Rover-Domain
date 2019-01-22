import numpy as np
from parameters import Parameters as p
import random
import pyximport; pyximport.install() # For cython(pyx) code

cdef class Ccea:
    cdef public double mut_prob
    cdef public double epsilon
    cdef public int n_populations
    cdef public int population_size
    cdef public int policy_size
    cdef public double[:, :, :] pops
    cdef public double[:, :] fitness
    cdef public int[:, :] team_selection

    def __init__(self):
        self.mut_prob = p.mutation_rate
        self.epsilon = p.epsilon
        self.n_populations = p.number_of_agents  # One population for each rover
        self.population_size  = p.population_size*2  # Number of policies in each pop
        n_inputs = p.number_of_inputs
        n_outputs = p.number_of_outputs
        n_nodes = p.number_of_nodes  # Number of nodes in hidden layer
        self.policy_size = (n_inputs + 1)*n_nodes + (n_nodes + 1)*n_outputs  # Number of weights for NN

        self.pops = np.zeros((self.n_populations, self.population_size, self.policy_size))
        self.fitness = np.zeros((self.n_populations, self.population_size))
        self.team_selection = np.zeros((self.n_populations, self.population_size), dtype = np.int32)

        cdef int pop_index, policy_index, w
        # Initialize a random population of NN weights
        for pop_index in range(self.n_populations):
            for policy_index in range(self.population_size):
                for w in range(self.policy_size):
                    self.pops[pop_index, policy_index, w] = random.uniform(-1, 1)
                self.team_selection[pop_index, policy_index] = -1

    cpdef select_policy_teams(self):  # Create policy teams for testing
        cdef int pop_id, policy_id, j, k, rpol
        for pop_id in range(self.n_populations):
            for policy_id in range(self.population_size):
                self.team_selection[pop_id, policy_id] = -1

        for pop_id in range(self.n_populations):
            for j in range(self.population_size):
                rpol = random.randint(0, (self.population_size - 1))
                k = 0
                while k < j:  # Make sure unique number is chosen
                    if rpol == self.team_selection[pop_id, k]:
                        rpol = random.randint(0, (self.population_size - 1))
                        k = -1
                    k += 1
                self.team_selection[pop_id, j] = rpol  # Assign policy to team
                # print('Pop: ', pop_id, ' Policy Team: ', self.team_selection[pop_id, j])

    cpdef reset_populations(self):  # Re-initializes CCEA populations for new run
        cdef int pop_index, policy_index, w
        for pop_index in range(self.n_populations):
            for policy_index in range(self.population_size):
                for w in range(self.policy_size):
                    self.pops[pop_index, policy_index, w] = random.uniform(-1, 1)

    cpdef mutate(self, half_length):
        cdef int pop_index, policy_index, target
        cdef double rvar
        for pop_index in range(self.n_populations):
            policy_index = half_length
            while policy_index < self.population_size:
                rvar = random.uniform(0, 1)
                if rvar <= self.mut_prob:
                    target = random.randint(0, (self.policy_size - 1))  # Select random weight to mutate
                    self.pops[pop_index, policy_index, target] = random.uniform(-1, 1)
                policy_index += 1

    cpdef create_new_pop(self):
        cdef int half_pop_length = self.population_size/2
        self.mutate(half_pop_length)  # Bottom half goes through mutation

    cpdef epsilon_greedy_select(self):  # Replace the bottom half with parents from top half
        cdef int pop_id, policy_id, k, parent
        cdef double rvar
        cdef int half_pop_length = self.population_size/2
        for pop_id in range(self.n_populations):
            policy_id = half_pop_length
            while policy_id < self.population_size:
                rvar = random.uniform(0, 1)
                if rvar >= self.epsilon:  # Choose best policy
                    # print('Keep Best')
                    for k in range(self.policy_size):
                        self.pops[pop_id, policy_id, k] = self.pops[pop_id, 0, k]  # Best policy
                else:
                    parent = random.randint(0, self.population_size/2)  # Choose a random parent
                    for k in range(self.policy_size):
                        self.pops[pop_id, policy_id, k] = self.pops[pop_id, parent, k]  # Random policy
                policy_id += 1

    cpdef down_select(self):
        cdef int pop_id, j, k
        # Reorder populations in terms of fitness (top half = best policies)
        for pop_id in range(self.n_populations):
            for j in range(self.population_size):
                k = j + 1
                while k < self.population_size:
                    if self.fitness[pop_id, j] < self.fitness[pop_id, k]:
                        self.fitness[pop_id, j], self.fitness[pop_id, k] = self.fitness[pop_id, k], self.fitness[pop_id, j]
                        self.pops[pop_id, j], self.pops[pop_id, k] = self.pops[pop_id, k], self.pops[pop_id, j]
                    k += 1

        # print('Pop-Size: ', self.population_size)
        # for pop_id in range(self.n_populations):
        #     print('Population: ', pop_id)
        #     for j in range(self.population_size):
        #         print(self.fitness[pop_id, j])

        self.epsilon_greedy_select()
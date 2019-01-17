import numpy as np
cimport cython

cdef extern from "math.h":
    double sqrt(double m)

@cython.boundscheck(False)  # Deactivate bounds checking
@cython.wraparound(False)   # Deactivate negative indexing.
cpdef get_agent_state(data):
    """
     Sensor model is <aNE, aNW, aSW, aSE, pNE, pNE, pSW, pSE>
     Where a means (other) agent, p means poi, and the rest are the quadrants
    """
    cdef int number_agents = data['Number of Agents']
    cdef int number_pois = data['Number of POIs']
    cdef double min_sqr_dist = data["Minimum Distance"] ** 2
    cdef double[:, :] agent_positions = data["Agent Positions"]
    cdef double[:] poi_values = data['Poi Values']
    cdef double[:, :] poi_positions = data["Poi Positions"]
    cdef double[:, :] agent_orientations = data["Agent Orientations"]
    cdef double[:, :] agent_state = np.zeros((number_agents, 8), dtype = np.float64)
    cdef int agent_id, other_agent_id, poi_id
    cdef double pos_vec_global_x, pos_vec_global_y
    cdef double pos_vec_agent_x, pos_vec_agent_y
    cdef double sqr_dist

    for agent_id in range(number_agents):

        # calculate observation values due to other agents
        for other_agent_id in range(number_agents):

            # agents do not sense self (ergo skip self comparison)
            if agent_id == other_agent_id:
                continue

            # Calculate position vectors between agents with respect to global coordinate frame
            pos_vec_global_x = agent_positions[other_agent_id, 0] - agent_positions[agent_id, 0] # X-direction
            pos_vec_global_y = agent_positions[other_agent_id, 1] - agent_positions[agent_id, 1] # Y-direction

            # Calculate position vectors between agents with respect to local agent coordinate frame using rotation mat
            pos_vec_agent_x = agent_orientations[agent_id, 0] * pos_vec_global_x + agent_orientations[agent_id, 1] * pos_vec_global_y
            pos_vec_agent_y = agent_orientations[agent_id, 0] * pos_vec_global_y - agent_orientations[agent_id, 1] * pos_vec_global_x
            sqr_dist = pos_vec_agent_x * pos_vec_agent_x + pos_vec_agent_y * pos_vec_agent_y

            # By bounding distance value we implicitly bound sensor values
            if sqr_dist < min_sqr_dist:
                sqr_dist = min_sqr_dist

            # other is east of agent
            if pos_vec_agent_x > 0:
                # other is north-east of agent
                if pos_vec_agent_y > 0:
                    agent_state[agent_id, 0] += 1.0 / sqr_dist
                else: # other is south-east of agent
                    agent_state[agent_id, 3] += 1.0  / sqr_dist
            else:  # other is west of agent
                # other is north-west of agent
                if pos_vec_agent_y > 0:
                    agent_state[agent_id, 1] += 1.0  / sqr_dist
                else:  # other is south-west of agent
                    agent_state[agent_id, 2] += 1.0  / sqr_dist


        # calculate observation values due to pois
        for poi_id in range(number_pois):

            # Calculate position vectors between agent and POI with respect to global coordinate frame
            pos_vec_global_x = poi_positions[poi_id, 0] - agent_positions[agent_id, 0]
            pos_vec_global_y = poi_positions[poi_id, 1] - agent_positions[agent_id, 1]

            # Calculate position vectors between agent and POI with respect to local agent coordinate frame
            pos_vec_agent_x = agent_orientations[agent_id, 0] * pos_vec_global_x + agent_orientations[agent_id, 1] * pos_vec_global_y
            pos_vec_agent_y = agent_orientations[agent_id, 0] * pos_vec_global_y - agent_orientations[agent_id, 1] * pos_vec_global_x
            sqr_dist = pos_vec_agent_x * pos_vec_agent_x + pos_vec_agent_y * pos_vec_agent_y

            # By bounding distance value we implicitly bound sensor values
            if sqr_dist < min_sqr_dist:
                sqr_dist = min_sqr_dist

            # poi is east of agent
            if pos_vec_agent_x > 0:
                # poi is north-east of agent
                if pos_vec_agent_y > 0:
                    agent_state[agent_id, 4] += poi_values[poi_id]  / sqr_dist
                else: # poi is south-east of agent
                    agent_state[agent_id, 7] += poi_values[poi_id]  / sqr_dist
            else:  # poi is west of agent
                # poi is north-west of agent
                if pos_vec_agent_y > 0:
                    agent_state[agent_id, 5] += poi_values[poi_id]  / sqr_dist
                else:  # poi is south-west of agent
                    agent_state[agent_id, 6] += poi_values[poi_id]  / sqr_dist

    #data["Agent Observations"] = joint_state_vec
    return agent_state


@cython.boundscheck(False)  # Deactivate bounds checking
@cython.wraparound(False)   # Deactivate negative indexing.
cpdef get_agent_actions(data, nn_output):
    cdef int number_agents = data['Number of Agents']
    action = np.zeros((number_agents, 2), dtype = np.float_)
    agent_policies = data["Agent Policies"]
    agent_state = data["Agent Observations"]

    cdef int agent_id
    for agent_id in range(number_agents):
        action[agent_id] = agent_policies[agent_id].get_action(agent_state[agent_id])
    data["Agent Actions"] = action


@cython.boundscheck(False)  # Deactivate bounds checking
@cython.wraparound(False)   # Deactivate negative indexing.
cpdef do_agent_move(data):
    cdef float world_width = data["World Width"]
    cdef float world_length = data["World Length"]
    cdef int number_agents = data['Number of Agents']
    cdef double[:, :] agent_positions = data["Agent Positions"]
    cdef double[:, :] agent_orientations = data["Agent Orientations"]
    agent_actions = np.array(data["Agent Actions"]).astype(np.float_)
    agent_actions = np.clip(agent_actions, -1, 1)
    cdef double[:, :] action = agent_actions
    cdef int agent_id
    cdef double dx, dy, norm # Change in x-position, change in y-position, total distance moved

    # move all agents
    for agent_id in range(number_agents):

        # turn action into global frame motion
        dx = agent_orientations[agent_id, 0] * action[agent_id, 0] - agent_orientations[agent_id, 1] * action[agent_id, 1]
        dy = agent_orientations[agent_id, 0] * action[agent_id, 1] + agent_orientations[agent_id, 1] * action[agent_id, 0]


        # globally move and reorient agent
        agent_positions[agent_id, 0] += dx
        agent_positions[agent_id, 1] += dy

        if dx == 0.0 and dy == 0.0:
            agent_orientations[agent_id, 0] = 1.0
            agent_orientations[agent_id, 1] = 0.0
        else:
            norm = sqrt(dx**2 +  dy**2)
            agent_orientations[agent_id, 0] = dx /norm
            agent_orientations[agent_id, 1] = dy /norm

        # # Check if action moves agent within the world bounds
        # if agent_positions[agent_id,0] > world_width:
        #     agent_positions[agent_id,0] = world_width
        # elif agent_positions[agent_id,0] < 0.0:
        #     agent_positions[agent_id,0] = 0.0
        #
        # if agent_positions[agent_id,1] > world_length:
        #     agent_positions[agent_id,1] = world_length
        # elif agent_positions[agent_id,1] < 0.0:
        #     agent_positions[agent_id,1] = 0.0


    data["Agent Positions"]  = agent_positions
    data["Agent Orientations"] = agent_orientations
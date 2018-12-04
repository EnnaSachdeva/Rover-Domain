# Dependencies: numpy, cython 

import datetime
from core import SimulationCore
import pyximport; pyximport.install() # For cython(pyx) code
from code.world_setup import * # Rover Domain Construction 
from code.agent_domain_2 import * # Rover Domain Dynamic  
from code.reward_2 import * # Agent Reward and Performance Recording 


"""
Provides Open AI gym wrapper for rover domain selfulation core with some extra
    gym-specific functionality. This is the gym equivalent to 'getSim()' in 
    the specific.py file.
    
    Get a default rover domain simulation with some default functionality.
    Users are encouraged to modify this function and save copies of it for
     each trial to use as a parameter reference.
    
Set data["Reward Function"] to define the reward function callback
Set data["Evaluation Function"] to define the evaluation function callback
Set data["Observation Function"] to define the observation funciton callback

Note: step function returns result of either the reward or evaluation function 
    depending mode ("Train" vs "Test" respectively)

RoverDomainCoreGym should be mods 
"""
class RoverDomainCoreGym(SimulationCore):
    def __init__(
        self,
    ):
        SimulationCore.__init__(self)
        
        self.data["Number of Agents"] = 30
        self.data["Number of POIs"] = 8
        self.data["Minimum Distance"] = 1.0
        self.data["Steps"] = 100
        self.data["Trains per Episode"] = 50
        self.data["Tests per Episode"] = 1
        self.data["Number of Episodes"] = 5000
        self.data["Specifics Name"] = "30Agents_8Poi_6Coup_Long_Comparison"
        self.data["Mod Name"] = "global"
        
        # Add Rover Domain Construction Functionality
        # Note: reset() will generate random world based on seed
        self.data["World Width"] = 50
        self.data["World Length"] = 50
        self.data['Poi Static Values'] = np.array([1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0])
        self.data['Poi Relative Static Positions'] = np.array([
            [0.0, 0.0], 
            [0.0, 1.0], 
            [1.0, 0.0], 
            [1.0, 1.0], 
            [1.0, 0.5], 
            [0.5, 1.0], 
            [0.0, 5.0],
            [0.5, 0.0]
        ])
        self.data['Agent Initialization Size'] = 0.1
        self.trainBeginFuncCol.append(blueprintStatic)
        self.trainBeginFuncCol.append(blueprintAgentInitSize)
        self.worldTrainBeginFuncCol.append(initWorld)
        self.testBeginFuncCol.append(blueprintStatic)
        self.testBeginFuncCol.append(blueprintAgentInitSize)
        self.worldTestBeginFuncCol.append(initWorld)
    
    
        # Add Rover Domain Dynamic Functionality
        """
        step() parameter [action] (2d numpy array with double precision):
            Actions for all rovers before clipping -1 to 1 defined by 
            doAgentMove.
            Dimensions are agentCount by 2.
            
        step()/reset() return [observation] (2d numpy array with double
            precision): Observation for all agents defined bydata["Observation 
            Function"].
            Dimensions are agentCount by 8.
            
        """
        self.data["Observation Function"] = doAgentSense
        self.worldTrainStepFuncCol.append(doAgentMove)        
        self.worldTestStepFuncCol.append(doAgentMove)

        
            
        # Add Agent Training Reward and Evaluation Functionality
        """
        Training Mode:
        step() return [reward] (1d numpy array with double precision): Reward 
            defined by data["Reward Function"]
            Length is agentCount.
            
        Testing Mode:
        step() return [reward] (double): Performance defined by 
            data["Evaluation Function"]
        """
        self.data["Coupling"] = 6
        self.data["Observation Radius"] = 4.0
        self.data["Reward Function"] = assignGlobalReward
        self.data["Evaluation Function"] = assignGlobalReward
        
        
        # Setup world for first time
        self.reset(mode = "Train", fullyResetting = True)
        
    def step(self, action):
        """
        Proceed 1 time step in world if world is not done
        
        Args:
        action: see rover domain dynamic functionality comments in __init__()
        
        Returns:
        observation: see rover domain dynamic functionality comments in 
            __init__()
        reward: see agent training reward functionality comments for 
            data["Mode"] == "Test" and performance recording functionality 
            comment for data["Mode"] == "Test"
        done (boolean): Describes with the world is done or not
        info (dictionary): The state of the simulation as a dictionary of data
        
        """
        # Store Action for other functions to use
        self.data["Agent Actions"] = action
        
        
        # If not done, do all step functionality
        if self.data["Step Index"] < self.data["Steps"]:
            self.data["Agent Actions"] = action
            if self.data["Mode"] == "Train":
                for func in self.worldTrainStepFuncCol:
                    func(self.data)
                self.data["Reward Function"]()
            elif self.data["Mode"] == "Test":
                for func in self.worldTestStepFuncCol:
                    func(self.data)
                self.data["Evaluation Function"]()
            else:
                raise Exception(
                    'data["Mode"] should be set to "Train" or "Test"'
                )
                
            # Observe state, store result in self.data
            self.data["Observation Function"](self.data)
            
            # Increment step index for future step() calls
            self.data["Step Index"] += 1
        
        # Check if simulation is done
        done = False
        if self.data["Step Index"] >= self.data["Steps"]:
            done = True
        
        return self.data["Agent Observations"], self.data["Gym Reward"], \
            done, self.data
        
    def reset(self, mode = None, fullyResetting = False):
        """
        Reset the world 
            
        Args:
        mode (None, String): Set to "Train" to enable functions associated with 
            training mode. Set to "Test" to enable functions associated with 
            testing mode instead. If None, does not change current simulation 
            mode.
        fullyResetting (boolean): If true, do addition functions 
            (self.trainBeginFuncCol) when setting up world. Typically used for
            resetting the world for a different episode and/or different
            training/testing simulation mode.
            
        Returns:
        observation: see rover domain dynamic functionality comments in 
            __init__()
        """
        # Zero step index for future step() calls
        self.data["Step Index"] = 0
        
        # Set mode if not None
        if mode != None:
            self.data["Mode"] = mode
        
        # Execute setting functionality
        if self.data["Mode"] == "Train":
            if fullyResetting:
                for func in self.trainBeginFuncCol:
                    func(self.data)
            for func in self.worldTrainBeginFuncCol:
                func(self.data)
        elif self.data["Mode"] == "Test":
            if fullyResetting:
                for func in self.testBeginFuncCol:
                    func(self.data)
            for func in self.worldTestBeginFuncCol:
                func(self.data)
        else:
            raise Exception('data["Mode"] should be set to "Train" or "Test"')
        
        # Observe state, store result in self.data
        self.data["Observation Function"](self.data)
        
        return self.data["Agent Observations"]
        

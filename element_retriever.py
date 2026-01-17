#!/usr/bin/env python3
"""
element_retriever.py - Wolpertinger-style action space reduction for UI automation

The problem: An app has 200+ UI elements. The LLM must choose which to interact with.
Brute-force: Show all 200 to the LLM → expensive, slow, error-prone.
Wolpertinger: Embed elements + task → retrieve top-k relevant → LLM reasons over k.

Architecture:
┌─────────────────────────────────────────────────────────────────┐
│                          Task                                    │
│              "Send message to Ben in WhatsApp"                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Element Retriever                             │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│   │Task Encoder │    │Element Enc. │    │  k-NN Index │        │
│   └─────────────┘    └─────────────┘    └─────────────┘        │
│         │                   │                  │                │
│         └───────────────────┴──────────────────┘                │
│                             │                                   │
│                      Similarity Search                          │
│                             │                                   │
│                      Top-k Elements                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      LLM Reasoner                                │
│            (Only sees k elements, not 200)                      │
└─────────────────────────────────────────────────────────────────┘
"""

"""
Requirements:
    pip install numpy sentence-transformers

For training:
    pip install torch
"""

import json
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Tuple
from pathlib import Path

# Optional dependencies
try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False
    np = None

try:
    from sentence_transformers import SentenceTransformer
    HAS_SENTENCE_TRANSFORMERS = True
except ImportError:
    HAS_SENTENCE_TRANSFORMERS = False


@dataclass
class UIElement:
    """Represents a UI element from the accessibility tree."""
    id: str
    role: str
    title: Optional[str] = None
    value: Optional[str] = None
    actions: List[str] = field(default_factory=list)
    enabled: bool = True
    path: str = ""

    @property
    def text_content(self) -> str:
        """Combined text for embedding."""
        parts = [self.role.replace("AX", "")]
        if self.title:
            parts.append(self.title)
        if self.value:
            parts.append(self.value[:200])  # Truncate long values
        return " ".join(parts)

    @property
    def is_actionable(self) -> bool:
        return len(self.actions) > 0 and self.enabled


@dataclass
class NavigationContext:
    """Current navigation state (the scratch pad)."""
    current_path: List[str] = field(default_factory=list)
    landmarks: List[str] = field(default_factory=list)
    hypothesis: Optional[str] = None
    recent_actions: List[str] = field(default_factory=list)

    def to_text(self) -> str:
        parts = []
        if self.current_path:
            parts.append(f"Location: {' > '.join(self.current_path)}")
        if self.landmarks:
            parts.append(f"Landmarks: {', '.join(self.landmarks)}")
        if self.hypothesis:
            parts.append(f"Hypothesis: {self.hypothesis}")
        if self.recent_actions:
            parts.append(f"Recent: {'; '.join(self.recent_actions[-3:])}")
        return "\n".join(parts)


class ElementRetriever:
    """
    Wolpertinger-style retriever for UI elements.

    Embeds task + context → finds k-nearest elements → returns filtered action space.
    """

    def __init__(self, model_name: str = "all-MiniLM-L6-v2"):
        if HAS_SENTENCE_TRANSFORMERS:
            self.encoder = SentenceTransformer(model_name)
            self.embed_dim = self.encoder.get_sentence_embedding_dimension()
        else:
            self.encoder = None
            self.embed_dim = 384  # Fake dimension

        # Cache for element embeddings (reuse across calls)
        self._element_cache: Dict[str, np.ndarray] = {}

    def _encode(self, texts: List[str]) -> np.ndarray:
        """Encode texts to embeddings."""
        if self.encoder:
            return self.encoder.encode(texts, convert_to_numpy=True)
        else:
            # Random embeddings for testing without sentence-transformers
            return np.random.randn(len(texts), self.embed_dim).astype(np.float32)

    def embed_element(self, element: UIElement) -> np.ndarray:
        """
        Embed a UI element.

        Features:
        - Role (structural)
        - Text content (semantic)
        - Path depth (hierarchical)
        - Actionability (functional)
        """
        cache_key = f"{element.id}:{element.text_content}"
        if cache_key in self._element_cache:
            return self._element_cache[cache_key]

        # Combine structural and semantic info
        text = f"{element.role} {element.text_content}"
        if element.actions:
            text += f" [actions: {', '.join(element.actions[:3])}]"

        embedding = self._encode([text])[0]
        self._element_cache[cache_key] = embedding
        return embedding

    def embed_task(self, task: str, context: Optional[NavigationContext] = None) -> np.ndarray:
        """
        Embed the task + navigation context.

        The context helps retrieve elements relevant to WHERE we are,
        not just WHAT we're trying to do.
        """
        parts = [task]
        if context:
            if context.hypothesis:
                parts.append(f"Current state: {context.hypothesis}")
            if context.current_path:
                parts.append(f"In: {context.current_path[-1] if context.current_path else 'root'}")

        text = " | ".join(parts)
        return self._encode([text])[0]

    def retrieve(
        self,
        task: str,
        elements: List[UIElement],
        context: Optional[NavigationContext] = None,
        k: int = 20,
        actionable_only: bool = True
    ) -> List[Tuple[UIElement, float]]:
        """
        Retrieve top-k elements most relevant to the task.

        Returns: List of (element, score) tuples, sorted by relevance.
        """
        if actionable_only:
            elements = [e for e in elements if e.is_actionable]

        if len(elements) <= k:
            # No need to filter, return all with dummy scores
            return [(e, 1.0) for e in elements]

        # Embed task
        task_emb = self.embed_task(task, context)

        # Embed all elements
        element_embs = np.array([self.embed_element(e) for e in elements])

        # Cosine similarity
        task_norm = task_emb / (np.linalg.norm(task_emb) + 1e-8)
        element_norms = element_embs / (np.linalg.norm(element_embs, axis=1, keepdims=True) + 1e-8)
        scores = element_norms @ task_norm

        # Get top-k indices
        top_k_idx = np.argsort(scores)[-k:][::-1]

        return [(elements[i], float(scores[i])) for i in top_k_idx]

    def clear_cache(self):
        """Clear element embedding cache (call when UI changes significantly)."""
        self._element_cache.clear()


# =============================================================================
# TRAINING
# =============================================================================

@dataclass
class TrajectoryStep:
    """One step in a successful trajectory."""
    task: str
    context: NavigationContext
    all_elements: List[UIElement]
    chosen_element_id: str
    action_type: str  # "click", "type", "navigate", etc.
    action_params: Dict
    success: bool  # Did this step make progress?


@dataclass
class Trajectory:
    """A complete task trajectory (successful or failed)."""
    task: str
    app_name: str
    steps: List[TrajectoryStep]
    completed: bool


class RetrieverTrainer:
    """
    Train the element retriever using contrastive learning.

    Training signal: In successful trajectories, the chosen element is a positive,
    other elements are negatives (with hard negative mining).

    Loss: InfoNCE / Contrastive loss

    Training data sources:
    1. Human demonstrations (most valuable)
    2. LLM-generated trajectories that succeeded
    3. Synthetic data from known UI patterns
    """

    def __init__(self, retriever: ElementRetriever):
        self.retriever = retriever
        self.trajectories: List[Trajectory] = []

    def add_trajectory(self, trajectory: Trajectory):
        """Add a trajectory to the training set."""
        if trajectory.completed:  # Only learn from successes
            self.trajectories.append(trajectory)

    def create_training_pairs(self) -> List[Dict]:
        """
        Create (query, positive, negatives) training pairs.

        For each step in a successful trajectory:
        - Query: task + context
        - Positive: the element that was actually chosen
        - Negatives: other elements (hard negatives = high similarity but wrong)
        """
        pairs = []

        for traj in self.trajectories:
            for step in traj.steps:
                if not step.success:
                    continue

                # Find the positive element
                positive = None
                negatives = []
                for elem in step.all_elements:
                    if elem.id == step.chosen_element_id:
                        positive = elem
                    else:
                        negatives.append(elem)

                if positive is None:
                    continue

                # Query = task + context
                query_text = f"{step.task} | {step.context.to_text()}"

                pairs.append({
                    "query": query_text,
                    "positive": positive.text_content,
                    "negatives": [n.text_content for n in negatives[:50]],  # Limit negatives
                    "metadata": {
                        "app": traj.app_name,
                        "action_type": step.action_type,
                        "element_role": positive.role
                    }
                })

        return pairs

    def compute_contrastive_loss(
        self,
        query_emb: np.ndarray,
        positive_emb: np.ndarray,
        negative_embs: np.ndarray,
        temperature: float = 0.07
    ) -> float:
        """
        InfoNCE loss for contrastive learning.

        L = -log(exp(q·p/τ) / (exp(q·p/τ) + Σ exp(q·n/τ)))
        """
        # Normalize
        q = query_emb / (np.linalg.norm(query_emb) + 1e-8)
        p = positive_emb / (np.linalg.norm(positive_emb) + 1e-8)
        n = negative_embs / (np.linalg.norm(negative_embs, axis=1, keepdims=True) + 1e-8)

        # Similarities
        pos_sim = np.dot(q, p) / temperature
        neg_sims = n @ q / temperature

        # InfoNCE
        logits = np.concatenate([[pos_sim], neg_sims])
        loss = -pos_sim + np.log(np.sum(np.exp(logits)))

        return float(loss)

    def train_epoch(self, pairs: List[Dict], lr: float = 0.001) -> float:
        """
        One training epoch (conceptual - actual training needs PyTorch/JAX).

        In practice, you'd:
        1. Use a trainable encoder (not frozen sentence-transformers)
        2. Compute gradients through the contrastive loss
        3. Update encoder weights

        This is a sketch showing the data flow.
        """
        total_loss = 0.0

        for pair in pairs:
            # Encode
            query_emb = self.retriever._encode([pair["query"]])[0]
            positive_emb = self.retriever._encode([pair["positive"]])[0]
            negative_embs = self.retriever._encode(pair["negatives"])

            # Compute loss
            loss = self.compute_contrastive_loss(query_emb, positive_emb, negative_embs)
            total_loss += loss

            # In real training: loss.backward(), optimizer.step()

        return total_loss / len(pairs) if pairs else 0.0


# =============================================================================
# HARD NEGATIVE MINING
# =============================================================================

class HardNegativeMiner:
    """
    Find hard negatives: elements that are similar to the positive but WRONG.

    These are the most valuable for training because they force the model
    to learn subtle distinctions.

    Examples of hard negatives:
    - Two buttons that look similar but do different things
    - Text fields with similar labels but different purposes
    - Elements in similar positions but different contexts
    """

    def __init__(self, retriever: ElementRetriever):
        self.retriever = retriever

    def mine_hard_negatives(
        self,
        query: str,
        positive: UIElement,
        all_elements: List[UIElement],
        k: int = 10
    ) -> List[UIElement]:
        """
        Find k elements that are:
        1. Similar to positive (high embedding similarity)
        2. But NOT the positive

        These are hard negatives that the model needs to learn to distinguish.
        """
        # Embed positive
        pos_emb = self.retriever.embed_element(positive)

        # Find similar elements
        similarities = []
        for elem in all_elements:
            if elem.id == positive.id:
                continue
            elem_emb = self.retriever.embed_element(elem)
            sim = np.dot(pos_emb, elem_emb) / (
                np.linalg.norm(pos_emb) * np.linalg.norm(elem_emb) + 1e-8
            )
            similarities.append((elem, sim))

        # Sort by similarity (descending) and take top-k
        similarities.sort(key=lambda x: x[1], reverse=True)
        return [elem for elem, _ in similarities[:k]]


# =============================================================================
# INTEGRATION WITH AGENT LOOP
# =============================================================================

class RetrievalAugmentedAgent:
    """
    Agent that uses retrieval to reduce action space before LLM reasoning.

    Flow:
    1. Observe UI → get all elements
    2. Retriever → filter to top-k relevant elements
    3. LLM → reason over k elements and choose action
    4. Execute action
    5. Log trajectory for future training
    """

    def __init__(
        self,
        retriever: ElementRetriever,
        llm_client,  # anthropic.Anthropic or similar
        k: int = 20
    ):
        self.retriever = retriever
        self.llm = llm_client
        self.k = k
        self.current_trajectory: Optional[Trajectory] = None

    def filter_elements(
        self,
        task: str,
        elements: List[UIElement],
        context: NavigationContext
    ) -> List[UIElement]:
        """Filter elements using retriever before showing to LLM."""
        results = self.retriever.retrieve(task, elements, context, k=self.k)
        return [elem for elem, score in results]

    def format_for_llm(self, elements: List[UIElement]) -> str:
        """Format filtered elements for LLM consumption."""
        lines = []
        for elem in elements:
            label = elem.title or elem.value or "(no label)"
            if len(label) > 60:
                label = label[:60] + "..."
            actions = ", ".join(elem.actions[:3]) if elem.actions else "none"
            lines.append(f"[{elem.id}] {elem.role}: {label} (actions: {actions})")
        return "\n".join(lines)

    def step(
        self,
        task: str,
        all_elements: List[UIElement],
        context: NavigationContext
    ) -> Dict:
        """
        One step of the agent loop:
        1. Filter elements
        2. Ask LLM
        3. Return action
        """
        # Filter
        filtered = self.filter_elements(task, all_elements, context)

        # Format for LLM
        elements_str = self.format_for_llm(filtered)

        # Build prompt
        prompt = f"""Task: {task}

Context:
{context.to_text()}

Available elements (filtered by relevance):
{elements_str}

What action should I take? Respond with a tool call."""

        # Call LLM (pseudocode - actual implementation depends on client)
        # response = self.llm.messages.create(...)
        # return parse_tool_call(response)

        return {
            "filtered_count": len(filtered),
            "total_count": len(all_elements),
            "prompt": prompt
        }


# =============================================================================
# EXAMPLE USAGE
# =============================================================================

def demo():
    """Demonstrate the retriever."""

    # Create some fake UI elements (in practice, these come from AppAgent)
    elements = [
        UIElement("e1", "AXButton", title="Send", actions=["AXPress"]),
        UIElement("e2", "AXButton", title="Cancel", actions=["AXPress"]),
        UIElement("e3", "AXTextField", title="Search", actions=["AXPress"]),
        UIElement("e4", "AXButton", value="Message from Ben: Hey!", actions=["AXPress"]),
        UIElement("e5", "AXButton", value="Message from Alice: Meeting at 3", actions=["AXPress"]),
        UIElement("e6", "AXTextArea", title="Type a message", actions=["AXPress"]),
        UIElement("e7", "AXButton", title="Attach", actions=["AXPress"]),
        UIElement("e8", "AXStaticText", value="WhatsApp"),
    ]

    # Create retriever
    retriever = ElementRetriever()

    # Query
    task = "Send a message to Ben"
    context = NavigationContext(hypothesis="In WhatsApp chat list")

    # Retrieve
    results = retriever.retrieve(task, elements, context, k=3)

    print(f"Task: {task}")
    print(f"Total elements: {len(elements)}")
    print(f"Retrieved top-3:")
    for elem, score in results:
        print(f"  [{elem.id}] {elem.role}: {elem.title or elem.value} (score: {score:.3f})")


if __name__ == "__main__":
    demo()

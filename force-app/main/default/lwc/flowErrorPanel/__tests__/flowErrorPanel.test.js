import { createElement } from 'lwc';
import FlowErrorPanel from 'c/flowErrorPanel';

describe('c-flow-error-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the provided headline and fault detail', () => {
        const element = createElement('c-flow-error-panel', { is: FlowErrorPanel });
        element.headline = 'Renewal failed';
        element.message = 'Only an active policy can be renewed';
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('.headline').textContent).toBe('Renewal failed');
            expect(element.shadowRoot.querySelector('.detail-text').textContent).toBe(
                'Only an active policy can be renewed'
            );
        });
    });

    it('falls back to a default headline when none is supplied', () => {
        const element = createElement('c-flow-error-panel', { is: FlowErrorPanel });
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('.headline').textContent).toBe('Something went wrong');
        });
    });
});

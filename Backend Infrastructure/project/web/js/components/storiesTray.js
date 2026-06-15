/**
 * Horizontal stories tray component.
 */

const storiesTrayComponent = {
    render({ groups, onAddStory, onSelectGroup }) {
        const tray = createEl('div', { className: 'stories-tray' });

        const addBtn = createEl('button', { className: 'story-circle add' });
        const ring = createEl('div', { className: 'ring avatar', style: 'width:60px;height:60px;' });
        ring.innerHTML = '<span class="plus">+</span>';
        addBtn.appendChild(ring);
        addBtn.appendChild(createEl('span', { className: 'name', text: 'Add Story' }));
        addBtn.addEventListener('click', onAddStory);
        tray.appendChild(addBtn);

        groups.forEach((group, index) => {
            const isViewed = group.stories.every(s => s.viewed);
            const btn = createEl('button', { className: 'story-circle' });
            const ringOuter = createEl('div', {
                className: 'story-ring' + (isViewed ? ' viewed' : ''),
                style: 'width:66px;height:66px;display:flex;align-items:center;justify-content:center;'
            });
            const avatar = renderAvatar(group.user, 56);
            ringOuter.appendChild(avatar);
            btn.appendChild(ringOuter);
            const name = createEl('span', { className: 'name', text: group.user.username });
            btn.appendChild(name);
            btn.addEventListener('click', () => onSelectGroup(index));
            tray.appendChild(btn);
        });

        return tray;
    }
};

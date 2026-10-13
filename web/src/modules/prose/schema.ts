import { defineArrayMember, defineField } from 'sanity'
import { BlockContentIcon } from '@sanity/icons/BlockContent'
import { ImageIcon } from '@sanity/icons/Image'
import { ThLargeIcon } from '@sanity/icons/ThLarge'
import { VscListTree } from 'react-icons/vsc'
import { getBlockText } from '@/lib/utils'
import defineModule from '@/sanity/schemaTypes/fragments/define-module'

export default defineModule({
	name: 'prose',
	title: 'Prose',
	type: 'object',
	icon: BlockContentIcon,
	groups: [
		{ name: 'content', default: true },
		{ name: 'sidebar' },
		{ name: 'options' },
	],
	fields: [
		defineField({
			name: 'content',
			type: 'array',
			of: [
				{ type: 'block' },
				defineArrayMember({
					type: 'image',
					icon: ImageIcon,
					options: {
						hotspot: true,
						metadata: ['lqip'],
					},
					fields: [
						defineField({
							name: 'alt',
							type: 'string',
						}),
						defineField({
							name: 'figcaption',
							type: 'array',
							of: [
								{
									type: 'block',
									styles: [{ title: 'Normal', value: 'normal' }],
								},
							],
						}),
					],
				}),
				defineArrayMember({
					type: 'code',
					title: 'Code block',
					options: { withFilename: true },
				}),
				{ type: 'custom-html' },
				// Shape the built-in PTE table editing binds to (sanity ships no `table` type).
				// Names must stay table/rows/row/cells/cell/value; `headerRows` enables the header toggle.
				defineArrayMember({
					name: 'table',
					type: 'object',
					icon: ThLargeIcon,
					fields: [
						defineField({ name: 'headerRows', type: 'number' }),
						defineField({
							name: 'rows',
							type: 'array',
							of: [
								defineArrayMember({
									name: 'row',
									type: 'object',
									fields: [
										defineField({
											name: 'cells',
											type: 'array',
											of: [
												defineArrayMember({
													name: 'cell',
													type: 'object',
													fields: [
														defineField({
															name: 'value',
															type: 'array',
															of: [defineArrayMember({ type: 'block' })],
														}),
													],
												}),
											],
										}),
									],
								}),
							],
						}),
					],
				}),
			],
			// Built-in PTE table editing (Studio ≥ 6.6) is off by default.
			components: {
				portableText: {
					plugins: (props) =>
						props.renderDefault({
							...props,
							plugins: { ...props.plugins, table: { enabled: true } },
						}),
				},
			},
			group: 'content',
		}),
		defineField({
			name: 'sidebar',
			type: 'sidebar',
			group: 'sidebar',
		}),
	],
	preview: {
		select: {
			content: 'content',
		},
		prepare: ({ content }) => ({
			title: getBlockText(content),
			subtitle: 'Prose',
		}),
	},
})

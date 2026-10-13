import { defineArrayMember, defineField, defineType } from 'sanity'
import { ThLargeIcon } from '@sanity/icons/ThLarge'

/**
 * Canonical table shape for the Portable Text Editor's built-in table editing
 * (`@portabletext/plugin-table`, bundled with Studio ≥ 6.6). Type and field names
 * must stay `table` / `rows` / `row` / `cells` / `cell` / `value` for the plugin to bind.
 */
export default defineType({
	name: 'table',
	title: 'Table',
	type: 'object',
	icon: ThLargeIcon,
	fields: [
		// Without this field the editor strips the header-row toggle silently.
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
})

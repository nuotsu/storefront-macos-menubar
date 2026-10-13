import { PortableText, type PortableTextTypeComponentProps } from 'next-sanity'
import type { Table } from '@/sanity/types'

type Row = NonNullable<Table['rows']>[number]

/** Renders the Portable Text Editor's built-in `table` block; the first `headerRows` rows go in `<thead>`. */
export default function ({ value }: PortableTextTypeComponentProps<Table>) {
	const rows = value.rows ?? []
	const headerCount = Math.min(value.headerRows ?? 0, rows.length)
	const head = rows.slice(0, headerCount)
	const body = rows.slice(headerCount)

	return (
		<table>
			{head.length > 0 && (
				<thead>
					{head.map((row) => (
						<TableRow key={row._key} row={row} as="th" />
					))}
				</thead>
			)}
			<tbody>
				{body.map((row) => (
					<TableRow key={row._key} row={row} as="td" />
				))}
			</tbody>
		</table>
	)
}

function TableRow({ row, as: Cell }: { row: Row; as: 'th' | 'td' }) {
	return (
		<tr>
			{row.cells?.map((cell) => (
				<Cell key={cell._key} className="text-left">
					<PortableText
						value={cell.value ?? []}
						// Cells hold blocks; drop the `<p>` wrapper so rows stay compact.
						components={{ block: { normal: ({ children }) => <>{children}</> } }}
					/>
				</Cell>
			))}
		</tr>
	)
}

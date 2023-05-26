// Just works for fastqc output for now

process MULTIQC {

	publishDir "$params.study_dir/multiqc", mode: 'copy'

	input:
	file ('fastqc/*')

	output:
	file "multiqc_report.html"
	
	"""
	multiqc $params.study_dir/fastqc
	"""
}